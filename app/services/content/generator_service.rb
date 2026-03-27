# app/services/content/generator_service.rb
#
# Fase 3 — Generazione contenuti AI
#
# Chiama Claude API (claude-opus-4-6) per generare i contenuti della landing page demo:
#   - generated_headline : titolo principale
#   - generated_about    : paragrafo descrittivo
#   - generated_services : array di servizi/prodotti tipici
#   - generated_cta      : call to action
#
# Crea (o aggiorna) il record Demo per la Company e avanza
# lo status a "demo_built".
#
# Uso:
#   result = Content::GeneratorService.call(company: company)
#   result.success?   # => true / false
#   result.demo       # => Demo
#   result.errors     # => Array<String>

module Content
  class GeneratorService
    ANTHROPIC_API_URL = "https://api.anthropic.com"
    MODEL             = "claude-opus-4-6"
    ANTHROPIC_VERSION = "2023-06-01"

    # Prompt di sistema: istruisce Claude a rispondere SOLO con JSON valido
    SYSTEM_PROMPT = <<~SYSTEM.strip
      Sei un esperto copywriter italiano specializzato in siti web per PMI locali.
      Il tuo compito è generare contenuti professionali, autentici e coinvolgenti
      per una landing page dimostrativa di un'attività italiana.

      Rispondi ESCLUSIVAMENTE con un oggetto JSON valido, senza markdown,
      senza delimitatori di codice, senza testo prima o dopo il JSON.

      Il JSON deve avere ESATTAMENTE questi quattro campi:
      {
        "headline": "string — titolo principale della pagina (max 80 caratteri, italiano)",
        "about": "string — paragrafo descrittivo dell'attività (150-250 parole, italiano)",
        "services": ["array di 4-6 stringhe — servizi o prodotti tipici dell'attività"],
        "cta": "string — call to action per il pulsante principale (max 50 caratteri, italiano)"
      }

      Regole:
      - Usa un tono professionale ma caldo, tipico delle PMI italiane
      - Rendi i contenuti specifici all'attività, non generici
      - L'headline deve catturare l'attenzione e includere il nome o la città
      - L'about deve citare punti di forza reali (qualità, esperienza, territorio)
      - I servizi devono essere realistici per la categoria indicata
      - Il CTA deve invitare all'azione (chiamare, visitare, contattare)
    SYSTEM

    Result = Struct.new(:demo, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(company:, http_client: nil)
      @company   = company
      @api_key   = ENV.fetch("ANTHROPIC_API_KEY") { raise "ANTHROPIC_API_KEY non configurata" }
      @client    = http_client || build_client
      @errors    = []
    end

    def call
      validate_company!

      Rails.logger.info "[GeneratorService] START company_id=#{@company.id} name=#{@company.name}"

      content = generate_content
      return Result.new(demo: nil, errors: @errors) if content.nil?

      demo = persist_demo(content)

      Rails.logger.info "[GeneratorService] DONE company_id=#{@company.id} demo_id=#{demo&.id}"
      Result.new(demo: demo, errors: @errors)
    rescue ArgumentError => e
      Rails.logger.warn "[GeneratorService] SKIP: #{e.message}"
      Result.new(demo: nil, errors: [e.message])
    end

    private

    # ─── Validazione ──────────────────────────────────────────────────────────

    def validate_company!
      unless %w[enriched demo_built].include?(@company.status)
        raise ArgumentError,
              "Company deve essere in stato 'enriched' o 'demo_built' " \
              "(attuale: #{@company.status})"
      end

      if @company.opted_out?
        raise ArgumentError, "Company ha fatto opt-out — skip generazione contenuti"
      end
    end

    # ─── Generazione via Claude API ───────────────────────────────────────────

    def generate_content
      prompt   = Content::PromptBuilder.build(company: @company)
      response = call_claude_api(prompt)
      return nil if response.nil?

      parse_claude_response(response)
    end

    def call_claude_api(prompt)
      body = {
        model:      MODEL,
        max_tokens: 2048,
        thinking:   { type: "adaptive" },
        system:     SYSTEM_PROMPT,
        messages:   [{ role: "user", content: prompt }]
      }

      response = @client.post("/v1/messages") do |req|
        req.headers["x-api-key"]         = @api_key
        req.headers["anthropic-version"] = ANTHROPIC_VERSION
        req.headers["content-type"]      = "application/json"
        req.body = JSON.generate(body)
      end

      unless response.status == 200
        data = JSON.parse(response.body) rescue {}
        @errors << "Claude API error #{response.status}: #{data.dig('error', 'message') || response.body.first(200)}"
        return nil
      end

      response
    rescue Faraday::Error => e
      @errors << "HTTP error Claude API: #{e.message}"
      nil
    end

    def parse_claude_response(response)
      data = JSON.parse(response.body)

      # Salta eventuali blocchi thinking → prendi solo il blocco text
      text_block = data["content"]&.find { |b| b["type"] == "text" }

      unless text_block
        @errors << "Nessun blocco 'text' nella risposta Claude"
        return nil
      end

      raw_json = text_block["text"].to_s.strip

      # Rimuovi eventuali delimitatori markdown (```json ... ```) difensivamente
      raw_json = raw_json.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip

      content = JSON.parse(raw_json)

      unless valid_content?(content)
        @errors << "Risposta Claude manca di campi richiesti: #{content.keys.inspect}"
        return nil
      end

      content
    rescue JSON::ParserError => e
      @errors << "JSON parsing error risposta Claude: #{e.message}"
      nil
    end

    def valid_content?(content)
      %w[headline about services cta].all? { |k| content.key?(k) } &&
        content["services"].is_a?(Array)
    end

    # ─── Persistenza Demo ─────────────────────────────────────────────────────

    def persist_demo(content)
      demo = Demo.find_or_initialize_by(company: @company)

      # Genera subdomain unico solo se è un nuovo record o quello attuale non è valido
      demo.subdomain = generate_subdomain if demo.new_record? || demo.subdomain.blank?

      demo.assign_attributes(
        generated_headline: content["headline"],
        generated_about:    content["about"],
        generated_services: JSON.generate(content["services"]),
        generated_cta:      content["cta"],
        expires_at:         30.days.from_now
      )

      unless demo.save
        @errors << "Demo save failed: #{demo.errors.full_messages.join(', ')}"
        return nil
      end

      # Avanza lo status della company
      unless @company.update(status: "demo_built")
        @errors << "Company status update failed: #{@company.errors.full_messages.join(', ')}"
      end

      demo
    end

    def generate_subdomain
      base = Demo.slugify(@company.name)
      base = "azienda" if base.blank?

      # Aggiungi città per leggibilità
      city_slug = @company.city.to_s.downcase
                           .gsub(/[àáâãä]/, "a").gsub(/[èéêë]/, "e")
                           .gsub(/[ìíîï]/, "i").gsub(/[òóôõö]/, "o")
                           .gsub(/[ùúûü]/, "u")
                           .gsub(/[^a-z0-9]/, "-").gsub(/-+/, "-").strip
      base = "#{base}-#{city_slug}" if city_slug.present?
      base = base.first(45)

      # Aggiungi suffix casuale per garantire unicità
      loop do
        candidate = "#{base}-#{SecureRandom.hex(3)}"
        break candidate unless Demo.exists?(subdomain: candidate)
      end
    end

    # ─── HTTP client ──────────────────────────────────────────────────────────

    def build_client
      Faraday.new(url: ANTHROPIC_API_URL) do |f|
        f.request :retry,
                  max:        2,
                  interval:   3.0,
                  exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
        f.options.timeout      = 90   # Claude con thinking può essere lento
        f.options.open_timeout = 10
      end
    end
  end
end
