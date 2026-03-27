# WebRadar — CLAUDE.md
> File di contesto cross-sessione. Aggiorna questo file ad ogni fase completata.
> Ultima versione: **Fase 6 + Mailgun Webhooks + Bug fix + Deploy + Privacy + RateLimit** ✅

---

## Cos'è WebRadar

Sistema automatizzato per:
1. Identificare PMI (ristoranti, artigiani, negozi, studi professionali) senza sito web tramite Google Places API + Playwright
2. Raccogliere dati pubblici (recensioni Maps, TripAdvisor, bio social)
3. Generare landing page demo personalizzate con AI (Claude API)
4. Deployarle su sottodominio dedicato (`nome-azienda.demo.webradar.it`)
5. Inviare email outreach personalizzata AI con link alla demo
6. Tracciare aperture/click in una dashboard Rails

**Scopo commerciale:** Vendere siti web alle aziende contattate tramite brand ad hoc.

---

## Stack Tecnologico (VINCOLO — non derogare senza indicazione esplicita)

### Backend
- **Ruby on Rails 8.0** (ultima stabile)
- **PostgreSQL 16** — database principale
- **Redis 7** — caching e supporto job
- **Solid Queue** — background jobs (nativo Rails 8, no Sidekiq salvo necessità)
- **Solid Cache** — caching su DB (nativo Rails 8)

### Frontend
- **Tailwind CSS** — styling (obbligatorio)
- **esbuild** — bundler JS (obbligatorio)
- **Vanilla JavaScript** — default, nessun framework JS salvo indicazione
- **Inertia.js + React** — solo se esplicitamente richiesto

### Autenticazione & Autorizzazione
- **Devise** — autenticazione
- **Pundit** — autorizzazione

### Storage & Infrastruttura
- **MinIO** — object storage S3-compatible in sviluppo/staging
- **Active Storage** — gestione file nativa Rails
- **Docker** — sviluppo locale e produzione
- **Kamal 2** — deploy in produzione

### Testing
- **Minitest** + **FactoryBot** + **Faker**

### Gems notevoli (giustificate)
| Gem            | Motivo                                               |
|----------------|------------------------------------------------------|
| discard        | Soft delete su Company e Lead                        |
| faraday        | HTTP client per Google Places API e Claude API       |
| liquid         | Template engine sicuro per generare HTML demo        |
| nokogiri       | Parsing HTML dai risultati scraping                  |
| mailgun-ruby   | Invio email transazionali                            |
| annotaterb     | Annota modelli con schema DB                         |

---

## Struttura Progetto

```
webradar/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb   ✅
│   │   ├── dashboard_controller.rb     ✅ (pipeline stats, email metrics, conversioni)
│   │   ├── tracking_controller.rb      ✅ (open pixel, click, opt-out)
│   │   ├── demo_previews_controller.rb ✅ (serve HTML demo in sviluppo, skip auth)
│   │   └── admin/
│   │       ├── base_controller.rb      ✅
│   │       ├── companies_controller.rb ✅ (index, show, discover, enrich, generate_content, build_demo, send_email, batch_generate, batch_build, batch_email, mark_replied, mark_converted)
│   │       ├── leads_controller.rb     ✅ (index, show, filtri outcome/opened/clicked)
│   │       └── demos_controller.rb     ✅ (index, show, filtri deployed/expired)
│   ├── models/
│   │   ├── application_record.rb       ✅
│   │   ├── user.rb                     ✅
│   │   ├── company.rb                  ✅
│   │   ├── demo.rb                     ✅
│   │   ├── lead.rb                     ✅
│   │   └── email_event.rb              ✅
│   ├── helpers/
│   │   └── application_helper.rb       ✅ (nav_link_class, status_badge)
│   ├── views/
│   │   ├── layouts/application.html.erb ✅
│   │   ├── layouts/admin.html.erb       ✅
│   │   ├── dashboard/index.html.erb     ✅
│   │   ├── tracking/opt_out_confirmed.html.erb ✅
│   │   └── admin/companies/
│   │       ├── index.html.erb           ✅ (lista + filtri + modal discovery)
│   │       └── show.html.erb            ✅ (dettaglio + foto + azioni pipeline)
│   ├── jobs/
│   │   ├── application_job.rb          ✅
│   │   ├── discovery_job.rb            ✅ (retry, logging, validazione categoria)
│   │   ├── enrichment_job.rb           ✅ (singola company + batch)
│   │   ├── content_generation_job.rb   ✅ (queue :demo, singola + batch)
│   │   ├── demo_build_job.rb           ✅ (queue :demo, render Liquid + deploy su disco)
│   │   └── outreach_email_job.rb       ✅ (queue :email, crea Lead, invia Mailgun, tracking)
│   ├── services/
│   │   └── discovery/
│   │       ├── google_places_service.rb  ✅ (Text Search + Place Details + upsert)
│   │       ├── browser_service.rb        ✅ (wrapper Ferrum headless)
│   │       ├── review_fetcher_service.rb ✅ (Places API reviews field)
│   │       ├── email_extractor_service.rb ✅ (orchestratore PagineGialle → Facebook)
│   │       ├── enrichment_service.rb     ✅ (orchestratore Fase 2, DI-friendly)
│   │       └── strategies/
│   │   ├── content/
│   │   │   ├── prompt_builder.rb         ✅ (costruisce prompt da Company + recensioni)
│   │   │   └── generator_service.rb      ✅ (Claude API claude-opus-4-6, crea Demo)
│   │   ├── demo/
│   │   │   ├── template_renderer.rb      ✅ (Liquid → HTML string, DI-friendly)
│   │   │   └── deploy_service.rb         ✅ (scrive HTML su disco, aggiorna deployed_at)
│   │   └── outreach/
│   │       ├── email_builder.rb          ✅ (Liquid email template, URL tracking, opt-out)
│   │       └── mailgun_service.rb        ✅ (invia via Mailgun API, client iniettabile)
│   │           ├── pagine_gialle_strategy.rb ✅ (Faraday + Nokogiri)
│   │           └── facebook_strategy.rb      ✅ (Ferrum)
│   ├── policies/
│   │   └── application_policy.rb       ✅
│   └── views/
│       ├── demo_templates/
│       │   └── default.html.liquid     ✅ (template responsive, CSS inline, no CDN)
│       ├── outreach/
│       │   └── email.html.liquid       ✅ (HTML email table-based, pixel + tracking URLs)
│       ├── dashboard/
│       │   └── index.html.erb          ✅ (pipeline, email metrics, conversioni, attività)
│       └── admin/
│           ├── leads/
│           │   ├── index.html.erb      ✅ (filtri, paginated, badge outcome)
│           │   └── show.html.erb       ✅ (timeline eventi, preview email, lead status)
│           └── demos/
│               ├── index.html.erb      ✅ (filtri deployed/expired, view count)
│               └── show.html.erb       ✅ (contenuti AI, stats views, lead collegato)
├── config/
│   ├── application.rb                  ✅
│   ├── boot.rb                         ✅
│   ├── routes.rb                       ✅
│   ├── database.yml                    ✅
│   ├── storage.yml                     ✅
│   ├── deploy.yml                      ✅ (Kamal 2)
│   ├── solid_queue.yml                 ✅
│   ├── environments/
│   │   ├── development.rb              ✅
│   │   └── production.rb               ✅
│   ├── initializers/
│   │   └── devise.rb                   ✅
│   └── locales/
│       └── it.yml                      ✅
├── db/
│   ├── migrate/
│   │   ├── 20240101000001_devise_create_users.rb       ✅
│   │   ├── 20240101000002_create_companies.rb          ✅
│   │   ├── 20240101000003_create_demos.rb              ✅
│   │   ├── 20240101000004_create_leads.rb              ✅
│   │   ├── 20240101000005_create_email_events.rb       ✅
│   │   ├── 20240101000006_create_solid_queue_tables.rb ✅
│   │   └── 20260319000001_add_enrichment_fields_to_companies.rb ✅ (reviews_data jsonb, enriched_at)
│   └── seeds.rb                        ✅
├── docker/
│   └── entrypoint.sh                   ✅
├── test/
│   ├── test_helper.rb                  ✅
│   ├── factories.rb                    ✅
│   ├── models/
│   │   └── company_test.rb             ✅
│   └── services/
│       ├── discovery/
│       │   ├── google_places_service_test.rb     ✅
│       │   ├── enrichment_service_test.rb        ✅
│       │   └── strategies/
│       │       └── pagine_gialle_strategy_test.rb ✅
│       ├── content/
│       │   └── generator_service_test.rb         ✅
│       ├── demo/
│       │   ├── template_renderer_test.rb         ✅
│       │   └── deploy_service_test.rb            ✅
│       └── outreach/
│           ├── email_builder_test.rb             ✅
│           └── mailgun_service_test.rb           ✅
├── app/assets/stylesheets/
│   └── application.tailwind.css        ✅
├── app/javascript/
│   └── application.js                  ✅
├── Gemfile                             ✅
├── Dockerfile                          ✅ (multi-stage produzione)
├── Dockerfile.dev                      ✅ (sviluppo)
├── docker-compose.yml                  ✅
├── tailwind.config.js                  ✅
├── package.json                        ✅
├── .ruby-version                       ✅ (3.3.4)
├── .env.example                        ✅
├── .gitignore                          ✅
└── CLAUDE.md                           ✅ (questo file)
```

---

## Modelli e Schema DB

### User
```
id, email, encrypted_password, reset_password_token,
first_name, last_name, role (operator/admin),
discarded_at, created_at, updated_at
```

### Company
```
id, name, category, address, city, province, phone,
google_place_id (unique), maps_rating, maps_reviews_count,
has_website (bool), maps_photo_urls (array),
email, email_source, email_status (found/manual/skip/unknown),
status (discovered→enriched→demo_built→contacted→replied→converted/opted_out),
reviews_data (jsonb array — [{author, rating, text, date}, ...]),
enriched_at,
opted_out_at, discarded_at, notes, created_at, updated_at
```

### Demo
```
id, company_id, subdomain (unique), html_path,
deployed_at, expires_at, view_count, last_viewed_at,
generated_headline, generated_about, generated_services, generated_cta,
created_at, updated_at
```

### Lead
```
id, company_id, demo_id,
email_sent_at, email_opened_at, link_clicked_at, replied_at,
reply_content, outcome (pending/interested/not_interested/converted/opted_out),
email_subject, email_body_snapshot, provider_message_id,
tracking_token (unique), created_at, updated_at
```

### EmailEvent
```
id, lead_id, event_type (sent/opened/clicked/bounced/opted_out),
occurred_at, metadata (jsonb), created_at, updated_at
```

---

## Variabili d'Ambiente

```bash
# App
RAILS_ENV=development
SECRET_KEY_BASE=
RAILS_MASTER_KEY=

# Database
DATABASE_URL=postgresql://webradar:password@postgres:5432/webradar_development
POSTGRES_USER=webradar
POSTGRES_PASSWORD=password
POSTGRES_DB=webradar_development

# Redis
REDIS_URL=redis://redis:6379/0

# MinIO
MINIO_ENDPOINT=http://minio:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_BUCKET=webradar
MINIO_REGION=us-east-1

# API
GOOGLE_PLACES_API_KEY=      # ← da attivare
ANTHROPIC_API_KEY=          # ← da attivare

# Email
SENDGRID_API_KEY=
MAILGUN_API_KEY=            # ← da attivare
MAILGUN_DOMAIN=

# Brand
BRAND_NAME=WebRadar
BRAND_EMAIL=info@webradar.it
DEMO_BASE_DOMAIN=demo.webradar.it
DEMO_STORAGE_PATH=                 # ← default: Rails.root/storage/demos
APP_BASE_URL=https://app.webradar.it  # ← usato per tracking URL nelle email

# GDPR
OPTOUT_SECRET=
```

---

## Servizi Docker

| Service      | Image               | Port locale | Note                         |
|--------------|---------------------|-------------|------------------------------|
| web          | build: Dockerfile.dev | 3000      | Rails app                    |
| worker       | build: Dockerfile.dev | —         | Solid Queue worker           |
| postgres     | postgres:16-alpine  | 5432        | Database principale          |
| redis        | redis:7-alpine      | 6379        | Cache + job support          |
| minio        | minio/minio         | 9000, 9001  | Object storage               |
| minio-setup  | minio/mc            | —           | Crea bucket al primo avvio   |
| mailhog      | mailhog/mailhog     | 1025, 8025  | Catch email in sviluppo      |

---

## Comandi Utili

```bash
# Avvio completo
docker compose up --build

# Solo DB + servizi (senza Rails, per sviluppo nativo)
docker compose up postgres redis minio mailhog

# Comandi Rails dentro Docker
docker compose exec web rails console
docker compose exec web rails db:create db:migrate db:seed
docker compose exec web rails test
docker compose exec web rails routes | grep -v devise

# Build assets
docker compose exec web yarn build
docker compose exec web yarn build:css

# Log
docker compose logs -f web
docker compose logs -f worker

# Reset completo DB
docker compose exec web rails db:drop db:create db:migrate db:seed

# Kamal (deploy produzione — da configurare)
kamal setup
kamal deploy
kamal app logs
```

---

## Route principali

```
GET  /auth/login              → Devise sign in
GET  /                        → redirect /auth/login (non autenticato)
GET  /                        → dashboard#index (autenticato)

GET  /t/:token/open           → tracking#open   (pixel email)
GET  /t/:token/click          → tracking#click  (redirect → demo)
GET  /t/:token/optout         → tracking#opt_out (GDPR)

GET  /admin/companies                           → lista aziende
GET  /admin/companies/:id                       → dettaglio azienda
POST /admin/companies/discover                  → avvia DiscoveryJob
POST /admin/companies/batch_enrich              → EnrichmentJob batch
POST /admin/companies/batch_generate            → ContentGenerationJob batch
POST /admin/companies/batch_build               → DemoBuildJob batch
POST /admin/companies/batch_email               → OutreachEmailJob batch
POST /admin/companies/:id/enrich                → EnrichmentJob singola
POST /admin/companies/:id/generate_content      → ContentGenerationJob singola
POST /admin/companies/:id/build_demo            → DemoBuildJob singola
POST /admin/companies/:id/send_email            → OutreachEmailJob singola
GET  /demos/:subdomain                          → DemoPreviewsController#show (dev preview)
GET  /admin/leads                               → lista lead (filtri outcome/opened/clicked)
GET  /admin/leads/:id                           → dettaglio lead + timeline eventi
GET  /admin/demos                               → lista demo (filtri deployed/expired)
GET  /admin/demos/:id                           → dettaglio demo + stats + link preview

GET  /up                      → health check (200 OK)
```

---

## Fasi di Sviluppo

| Fase | Descrizione                              | Status        |
|------|------------------------------------------|---------------|
| 0    | Setup Rails + Docker + modelli base      | ✅ Completata  |
| 1    | Google Places API → Discovery Service    | ✅ Completata  |
| 2    | Enrichment (reviews + email extractor)   | ✅ Completata  |
| 3    | Claude AI → generazione contenuti        | ✅ Completata  |
| 4    | Demo Builder (HTML) + Deploy sottodominio| ✅ Completata  |
| 5    | Email Outreach (Mailgun) + tracking      | ✅ Completata  |
| 6    | Dashboard tracking + Lead management     | ✅ Completata  |
| —    | Bug fix critici pre-produzione           | ✅ Completata  |
| —    | Mailgun Webhooks (tracking server-side)  | ✅ Completata  |
| —    | Deploy Kamal 2 + nginx wildcard          | ✅ Completata  |
| —    | Privacy Policy + Rate limiting           | ✅ Completata  |

---

## Mailgun Webhooks (post Fase 6)

Ricezione eventi in tempo reale da Mailgun per aggiornare automaticamente Lead e EmailEvent.

| File | Descrizione |
|------|-------------|
| `app/controllers/webhooks/mailgun_controller.rb` | Controller webhook con verifica HMAC-SHA256, gestione eventi, idempotenza via `mailgun_event_id` |
| `app/services/outreach/mailgun_service.rb` | Aggiunto `tracking_token:` → passato come `v:tracking_token` custom variable a Mailgun |
| `app/jobs/outreach_email_job.rb` | Passa `tracking_token: lead.tracking_token` al MailgunService |
| `config/routes.rb` | `POST /webhooks/mailgun` (no CSRF, no auth) |
| `test/controllers/webhooks/mailgun_controller_test.rb` | 11 test: firma HMAC, opened/clicked/complained/failed, idempotenza |

**Env var aggiunta:** `MAILGUN_WEBHOOK_SECRET` (Sending → Webhooks → "Webhook signing key" nel pannello Mailgun)

**Setup Mailgun:** Dashboard → Sending → Webhooks → URL: `https://app.webradar.it/webhooks/mailgun`
Abilitare: `opened`, `clicked`, `bounced`, `complained`, `unsubscribed`, `failed`

**Mapping eventi Mailgun → EmailEvent:**

| Evento Mailgun | Lead | Company | EmailEvent |
|----------------|------|---------|------------|
| `opened` | `email_opened_at` (solo prima) | — | `"opened"` |
| `clicked` | `link_clicked_at` (solo primo) | — | `"clicked"` |
| `complained`/`unsubscribed` | `outcome = "opted_out"` | `opted_out_at`, `status = "opted_out"` | `"opted_out"` |
| `failed`/`bounced` | — | — | `"bounced"` + reason |

---

## Bug Fix Critici (post Fase 6)

| Fix | File | Dettaglio |
|-----|------|-----------|
| `mark_replied`/`mark_converted` | `admin/companies_controller.rb` | Aggiorna anche `Lead#replied_at`, `Lead#outcome` e crea `EmailEvent("replied")` |
| Colonna rinominata | `db/migrate/20260319000002_rename_sendgrid_message_id_in_leads.rb` | `sendgrid_message_id` → `provider_message_id` (Mailgun, non SendGrid) |
| Job aggiornato | `app/jobs/outreach_email_job.rb` | Usa `provider_message_id:` dopo la migrazione |
| Path traversal demo | `app/controllers/demo_previews_controller.rb` | Valida `html_path` con `File.expand_path` contro `DEMO_STORAGE_PATH` |
| Docker volume | `docker-compose.yml` | Aggiunto volume named `demos_storage` su `web` e `worker` |
| Env vars mancanti | `.env.example` | Aggiunti `APP_BASE_URL` e `DEMO_STORAGE_PATH` |

---

## Deploy Kamal 2 + nginx (post Fase 6)

| File | Descrizione |
|------|-------------|
| `config/deploy.yml` | Kamal 2: server `web` + `worker`, `proxy` block (kamal-proxy), volumes `demos_storage`, tutti i secret |
| `config/nginx/demo-subdomain.conf` | Nginx wildcard `*.demo.webradar.it` → HTML statici in `/var/www/demos/{subdomain}/index.html` |
| `.kamal/hooks/post-deploy` | Hook automatico post-deploy: `rails db:migrate` |

**Setup VPS:**
1. DNS: `*.demo.webradar.it` → A → IP VPS (record wildcard)
2. SSL wildcard: `certbot --dns-cloudflare -d "demo.webradar.it" -d "*.demo.webradar.it"`
3. Nginx: `cp config/nginx/demo-subdomain.conf /etc/nginx/sites-available/demo.webradar.it && ln -s ...`
4. Symlink volume: `ln -s /var/lib/docker/volumes/webradar_demos_storage/_data /var/www/demos`
5. Deploy: `kamal setup && kamal deploy`

---

## Privacy Policy + Rate Limiting (post Fase 6)

| File | Descrizione |
|------|-------------|
| `app/controllers/pages_controller.rb` | `GET /privacy` — skip auth, passa `brand_name`/`brand_email` |
| `app/views/pages/privacy.html.erb` | Privacy Policy GDPR compliant in italiano (8 sezioni) |
| `config/routes.rb` | `get "/privacy"` → `pages#privacy` |
| `app/services/demo/template_renderer.rb` | Aggiunto `privacy_url` nelle variabili Liquid |
| `app/views/demo_templates/default.html.liquid` | Footer demo: link "Privacy Policy" → `{{ privacy_url }}` |
| `Gemfile` | Aggiunto `gem "rack-attack"` |
| `config/application.rb` | `config.middleware.use Rack::Attack` |
| `config/initializers/rack_attack.rb` | Throttle tracking (open/click/optout), webhook, login brute-force |

**Soglie Rack::Attack:**

| Endpoint | Limite | Periodo |
|----------|--------|---------|
| `/t/:token/open` | 60 req | 1 minuto |
| `/t/:token/click` | 20 req | 1 minuto |
| `/t/:token/optout` | 10 req | 1 minuto |
| `POST /webhooks/mailgun` | 200 req | 1 minuto |
| `POST /auth/login` (per IP) | 5 req | 20 secondi |
| `POST /auth/login` (per email) | 10 req | 1 minuto |

---

## Decisioni Architetturali

| Decisione | Scelta | Motivo |
|-----------|--------|--------|
| Job queue | Solid Queue | Nativo Rails 8, sufficiente per 10-50 az/ciclo |
| Demo format | HTML statico | Nessun server-side rendering, deploy nginx puro |
| Demo hosting | Nginx wildcard subdomain | `*.demo.webradar.it` → vhost dinamici |
| Soft delete | discard gem | Su Company e Lead — GDPR e audit trail |
| Template demo | Liquid | Sicuro, sandboxato, nessun rischio injection |
| Email tracking | Pixel 1x1 GIF + redirect link | Nativo, no dipendenze esterne |
| Opt-out | Token univoco in ogni email | GDPR compliant, 1-click |
| JS frontend | Vanilla + Turbo | Nessun React necessario per la dashboard |

---

## Note GDPR

- `opted_out_at` su Company → mai più contattata (check in `Company#contactable?`)
- `tracking_token` univoco per ogni Lead → usato per pixel open, click redirect, opt-out
- Footer email obbligatorio: brand name, P.IVA, motivo contatto
- Le foto Maps nelle demo citano fonte nel footer della landing
- Privacy Policy nel footer di ogni demo generata (da creare in Fase 4)
- `EmailEvent` con `metadata jsonb` → audit trail completo

---

## Contesto Business

- **Volume target**: 10-50 aziende per ciclo, ~200 az/mese
- **Budget API stimato**: 20-32 €/mese
- **Area geografica iniziale**: regione/provincia (configurabile)
- **Categorie target**: ristoranti, artigiani, negozi, studi professionali
- **Mittente email**: brand ad hoc (WebRadar o simile)
- **Trattativa post-risposta**: manuale (gestita dall'operatore)
- **Stack infrastruttura**: Docker locale → VPS con Kamal 2 in produzione
