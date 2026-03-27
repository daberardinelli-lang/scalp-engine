class CreateLeads < ActiveRecord::Migration[8.0]
  def change
    create_table :leads do |t|
      t.references :company, null: false, foreign_key: true
      t.references :demo,    null: true,  foreign_key: true

      t.datetime :email_sent_at
      t.datetime :email_opened_at
      t.datetime :link_clicked_at
      t.datetime :replied_at
      t.text     :reply_content

      # pending / interested / not_interested / converted / opted_out
      t.string   :outcome, default: "pending", null: false

      # Email metadata
      t.string   :email_subject
      t.text     :email_body_snapshot
      t.string   :sendgrid_message_id
      t.string   :tracking_token, null: false  # per open pixel e opt-out

      t.timestamps
    end

    add_index :leads, :outcome
    add_index :leads, :tracking_token, unique: true
    add_index :leads, :email_sent_at
  end
end
