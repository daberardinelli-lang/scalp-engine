class CreateDemos < ActiveRecord::Migration[8.0]
  def change
    create_table :demos do |t|
      t.references :company, null: false, foreign_key: true

      t.string   :subdomain,    null: false  # es: pizzeria-da-mario
      t.string   :html_path     # path su disco o S3
      t.datetime :deployed_at
      t.datetime :expires_at
      t.integer  :view_count,   default: 0
      t.datetime :last_viewed_at

      # Dati AI generati (snapshot)
      t.text     :generated_headline
      t.text     :generated_about
      t.text     :generated_services
      t.text     :generated_cta

      t.timestamps
    end

    add_index :demos, :subdomain, unique: true
    add_index :demos, :deployed_at
    add_index :demos, :expires_at
  end
end
