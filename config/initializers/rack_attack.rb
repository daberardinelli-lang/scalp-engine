# config/initializers/rack_attack.rb
#
# Rate limiting e protezione endpoint pubblici tramite Rack::Attack.
#
# Le soglie sono calibrate per il traffico atteso di WebRadar:
#   - Tracking email: 10-50 aziende/ciclo, email aperte da client/proxy
#   - Webhook Mailgun: burst di eventi dopo invii batch
#   - Admin: accesso umano, nessun burst legittimo
#
# In produzione Rack::Attack usa Redis come cache se disponibile,
# altrimenti cade back su ActiveSupport::Cache (DB via Solid Cache).

class Rack::Attack

  # ─── Cache store ──────────────────────────────────────────────────────────
  # Usa Redis in produzione (più veloce per incr/decr), Solid Cache negli altri env
  cache_store = if Rails.env.production? && ENV["REDIS_URL"].present?
                  ActiveSupport::Cache::RedisCacheStore.new(
                    url: ENV["REDIS_URL"],
                    namespace: "rack_attack"
                  )
                else
                  Rails.cache
                end

  Rack::Attack.cache.store = cache_store

  # ─── Safelist: loopback sempre libero ────────────────────────────────────
  safelist("loopback") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end

  # ─── Throttle: pixel apertura email (/t/:token/open) ─────────────────────
  # I client email (Gmail, Outlook, proxy) possono richiedere il pixel più volte.
  # 60 req/min per IP è generoso ma protegge da abuse automatico.
  throttle("tracking/open", limit: 60, period: 1.minute) do |req|
    req.ip if req.path =~ %r{\A/t/[^/]+/open\z}
  end

  # ─── Throttle: click su link demo (/t/:token/click) ──────────────────────
  # Un click umano dovrebbe avvenire una sola volta; 20/min per IP protegge
  # da click-bombing senza disturbare proxy legittimi.
  throttle("tracking/click", limit: 20, period: 1.minute) do |req|
    req.ip if req.path =~ %r{\A/t/[^/]+/click\z}
  end

  # ─── Throttle: opt-out (/t/:token/optout) ────────────────────────────────
  # Azione una-tantum; 10 req/min è abbondantemente sufficiente.
  throttle("tracking/optout", limit: 10, period: 1.minute) do |req|
    req.ip if req.path =~ %r{\A/t/[^/]+/optout\z}
  end

  # ─── Throttle: webhook Mailgun (/webhooks/mailgun) ───────────────────────
  # Mailgun può inviare burst di eventi dopo un invio batch (es. 50 "sent" tutti insieme).
  # 200 req/min è ragionevole; il traffic legittimo di Mailgun proviene da IP fissi.
  throttle("webhooks/mailgun", limit: 200, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/webhooks/mailgun"
  end

  # ─── Throttle: login Devise (/auth/login) ────────────────────────────────
  # Protezione brute-force: 5 tentativi/20 secondi per IP
  throttle("login/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.post? && req.path == "/auth/login"
  end

  # Protezione brute-force per email specifica: 10 tentativi/minuto
  throttle("login/email", limit: 10, period: 1.minute) do |req|
    if req.post? && req.path == "/auth/login"
      req.params.dig("user", "email").to_s.downcase.presence
    end
  end

  # ─── Risposta personalizzata per i throttled ─────────────────────────────
  throttled_responder = lambda do |env|
    now        = Time.current
    match_data = env["rack.attack.match_data"]

    headers = {
      "Content-Type"   => "application/json",
      "Retry-After"    => match_data[:period].to_s
    }

    body = { error: "Troppe richieste. Riprova tra #{match_data[:period]} secondi." }.to_json
    [429, headers, [body]]
  end

  self.throttled_responder = throttled_responder

  # ─── Logging ─────────────────────────────────────────────────────────────
  ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _request_id, payload|
    req   = payload[:request]
    match = req.env["rack.attack.matched"]
    Rails.logger.warn "[RackAttack] Throttled #{match} — IP: #{req.ip} PATH: #{req.path}"
  end
end
