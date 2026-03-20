# app/services/discovery/browser_service.rb
#
# Wrapper condiviso attorno a Ferrum (Chrome DevTools Protocol).
# Gestisce lifecycle del browser (avvio / shutdown) e configurazione
# headless uniforme per tutti i service che usano un browser.
#
# Uso:
#   Discovery::BrowserService.with_browser do |browser|
#     browser.go_to("https://example.com")
#     browser.body   # => HTML della pagina
#   end

module Discovery
  class BrowserService
    BROWSER_OPTIONS = {
      headless:       true,
      timeout:        30,
      process_timeout: 40,
      browser_options: {
        "no-sandbox":               nil,
        "disable-dev-shm-usage":    nil,
        "disable-gpu":              nil,
        "disable-setuid-sandbox":   nil,
        "disable-background-networking": nil
      }
    }.freeze

    # Risolve il percorso di Chromium: ENV > path standard Debian/Alpine
    CHROMIUM_PATHS = %w[
      /usr/bin/chromium
      /usr/bin/chromium-browser
      /usr/bin/google-chrome-stable
      /usr/bin/google-chrome
    ].freeze

    def self.with_browser(options: {}, &block)
      new(options).run(&block)
    end

    def initialize(options = {})
      @options = BROWSER_OPTIONS.merge(options)
    end

    def run
      browser = build_browser
      yield browser
    rescue Ferrum::TimeoutError => e
      raise BrowserTimeoutError, "Timeout browser: #{e.message}"
    rescue Ferrum::Error => e
      raise BrowserError, "Errore browser: #{e.message}"
    ensure
      browser&.quit
    end

    # ─── Errors ──────────────────────────────────────────────────────────────

    class BrowserError        < StandardError; end
    class BrowserTimeoutError < BrowserError;  end

    private

    def build_browser
      opts = @options.dup

      # Individua Chromium se non esplicitamente indicato
      unless opts[:browser_path] || ENV["BROWSER_PATH"]
        path = CHROMIUM_PATHS.find { |p| File.executable?(p) }
        opts[:browser_path] = path if path
      end

      opts[:browser_path] ||= ENV["BROWSER_PATH"] if ENV["BROWSER_PATH"]

      # Imposta User-Agent realistico per ridurre detection
      opts[:browser_options] = (opts[:browser_options] || {}).merge(
        "user-agent" => realistic_user_agent
      )

      Ferrum::Browser.new(opts)
    end

    def realistic_user_agent
      "Mozilla/5.0 (X11; Linux x86_64) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) " \
      "Chrome/121.0.0.0 Safari/537.36"
    end
  end
end
