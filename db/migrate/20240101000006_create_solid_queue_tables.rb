# Migrazione per Solid Queue — generata da: rails solid_queue:install:migrations
# Inclusa manualmente per completezza del progetto

class CreateSolidQueueTables < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_queue_jobs do |t|
      t.string  :queue_name,   null: false
      t.string  :class_name,   null: false
      t.text    :arguments
      t.integer :priority,     default: 0, null: false
      t.string  :active_job_id
      t.datetime :scheduled_at
      t.datetime :finished_at
      t.string  :concurrency_key
      t.timestamps
      t.index [:active_job_id]
      t.index [:class_name]
      t.index [:finished_at]
      t.index [:queue_name, :finished_at], name: "index_solid_queue_jobs_for_filtering"
      t.index [:scheduled_at, :finished_at], name: "index_solid_queue_jobs_for_alerting"
    end

    create_table :solid_queue_scheduled_executions do |t|
      t.references :job, null: false, index: { unique: true }
      t.string   :queue_name, null: false
      t.integer  :priority,   default: 0, null: false
      t.datetime :scheduled_at, null: false
      t.timestamps
      t.index [:scheduled_at, :priority, :job_id],
              name: "index_solid_queue_scheduled_executions_for_dispatch"
    end

    create_table :solid_queue_ready_executions do |t|
      t.references :job, null: false, index: { unique: true }
      t.string  :queue_name, null: false
      t.integer :priority,   default: 0, null: false
      t.timestamps
      t.index [:priority, :job_id], name: "index_solid_queue_ready_executions_for_dispatch"
      t.index [:queue_name, :priority, :job_id],
              name: "index_solid_queue_ready_executions_for_pop"
    end

    create_table :solid_queue_claimed_executions do |t|
      t.references :job,     null: false, index: { unique: true }
      t.bigint     :process_id
      t.datetime   :created_at, null: false
      t.index [:process_id, :job_id]
    end

    create_table :solid_queue_blocked_executions do |t|
      t.references :job, null: false, index: { unique: true }
      t.string   :queue_name,      null: false
      t.integer  :priority,        default: 0, null: false
      t.string   :concurrency_key, null: false
      t.datetime :expires_at,      null: false
      t.timestamps
      t.index [:expires_at, :concurrency_key, :priority, :job_id],
              name: "index_solid_queue_blocked_executions_for_release"
    end

    create_table :solid_queue_failed_executions do |t|
      t.references :job, null: false, index: { unique: true }
      t.text     :error
      t.datetime :created_at, null: false
    end

    create_table :solid_queue_pauses do |t|
      t.string   :queue_name, null: false, index: { unique: true }
      t.datetime :created_at, null: false
    end

    create_table :solid_queue_processes do |t|
      t.string   :kind,        null: false
      t.datetime :last_heartbeat_at, null: false
      t.bigint   :supervisor_id
      t.integer  :pid,         null: false
      t.string   :hostname
      t.text     :metadata
      t.timestamps
      t.index [:last_heartbeat_at]
      t.index [:supervisor_id]
    end

    create_table :solid_queue_semaphores do |t|
      t.string   :key,      null: false, index: { unique: true }
      t.integer  :value,    default: 1,  null: false
      t.datetime :expires_at, null: false
      t.timestamps
      t.index [:expires_at]
      t.index [:key, :value]
    end
  end
end
