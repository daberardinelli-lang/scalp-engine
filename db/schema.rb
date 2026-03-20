# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_19_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "companies", force: :cascade do |t|
    t.string "address"
    t.string "category", null: false
    t.string "city"
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.string "email"
    t.string "email_source"
    t.string "email_status", default: "unknown"
    t.datetime "enriched_at"
    t.string "google_place_id"
    t.boolean "has_website", default: false, null: false
    t.string "maps_photo_urls", default: [], array: true
    t.decimal "maps_rating", precision: 2, scale: 1
    t.integer "maps_reviews_count", default: 0
    t.string "name", null: false
    t.text "notes"
    t.datetime "opted_out_at"
    t.string "phone"
    t.string "province"
    t.jsonb "reviews_data", default: []
    t.string "status", default: "discovered", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_companies_on_category"
    t.index ["discarded_at"], name: "index_companies_on_discarded_at"
    t.index ["enriched_at"], name: "index_companies_on_enriched_at"
    t.index ["google_place_id"], name: "index_companies_on_google_place_id", unique: true
    t.index ["opted_out_at"], name: "index_companies_on_opted_out_at"
    t.index ["province"], name: "index_companies_on_province"
    t.index ["status"], name: "index_companies_on_status"
  end

  create_table "demos", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deployed_at"
    t.datetime "expires_at"
    t.text "generated_about"
    t.text "generated_cta"
    t.text "generated_headline"
    t.text "generated_services"
    t.string "html_path"
    t.datetime "last_viewed_at"
    t.string "subdomain", null: false
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0
    t.index ["company_id"], name: "index_demos_on_company_id"
    t.index ["deployed_at"], name: "index_demos_on_deployed_at"
    t.index ["expires_at"], name: "index_demos_on_expires_at"
    t.index ["subdomain"], name: "index_demos_on_subdomain", unique: true
  end

  create_table "email_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.bigint "lead_id", null: false
    t.jsonb "metadata", default: {}
    t.datetime "occurred_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_email_events_on_event_type"
    t.index ["lead_id"], name: "index_email_events_on_lead_id"
    t.index ["metadata"], name: "index_email_events_on_metadata", using: :gin
    t.index ["occurred_at"], name: "index_email_events_on_occurred_at"
  end

  create_table "leads", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.bigint "demo_id"
    t.text "email_body_snapshot"
    t.datetime "email_opened_at"
    t.datetime "email_sent_at"
    t.string "email_subject"
    t.datetime "link_clicked_at"
    t.string "outcome", default: "pending", null: false
    t.string "provider_message_id"
    t.datetime "replied_at"
    t.text "reply_content"
    t.string "tracking_token", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_leads_on_company_id"
    t.index ["demo_id"], name: "index_leads_on_demo_id"
    t.index ["email_sent_at"], name: "index_leads_on_email_sent_at"
    t.index ["outcome"], name: "index_leads_on_outcome"
    t.index ["tracking_token"], name: "index_leads_on_tracking_token", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at", "concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.datetime "updated_at", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_ready_executions_for_dispatch"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_ready_executions_for_pop"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_scheduled_executions_for_dispatch"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name", default: "", null: false
    t.string "last_name", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "operator", null: false
    t.datetime "updated_at", null: false
    t.index ["discarded_at"], name: "index_users_on_discarded_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "demos", "companies"
  add_foreign_key "email_events", "leads"
  add_foreign_key "leads", "companies"
  add_foreign_key "leads", "demos"
end
