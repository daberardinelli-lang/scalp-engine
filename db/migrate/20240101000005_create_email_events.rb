class CreateEmailEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :email_events do |t|
      t.references :lead, null: false, foreign_key: true

      # sent / opened / clicked / bounced / opted_out
      t.string   :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb    :metadata, default: {}

      t.timestamps
    end

    add_index :email_events, :event_type
    add_index :email_events, :occurred_at
    add_index :email_events, :metadata, using: :gin
  end
end
