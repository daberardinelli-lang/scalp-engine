class CreateCampaigns < ActiveRecord::Migration[8.0]
  def change
    create_table :campaigns do |t|
      t.references :user, null: true, foreign_key: true

      t.string  :name,                    null: false
      t.text    :description

      # Chi usa l'app e chi cerca
      t.string  :operator_profile        # es. "Informatore farmaceutico Roche"
      t.string  :target_profile          # es. "Medici di base provincia di Roma"

      # Discovery
      t.string  :discovery_source,       null: false, default: "google_places"
      t.string  :discovery_query         # query libera (es. "medici di base") o tipo Maps

      # Email
      t.string  :email_subject_template  # Liquid, es. "Proposta esclusiva per {{ company_name }}"
      t.string  :email_body_template     # path al file Liquid, es. "pharma_rep"

      # Feature flags
      t.boolean :use_demo,               null: false, default: false
      t.boolean :use_ai_content,         null: false, default: true
      t.boolean :active,                 null: false, default: true

      t.timestamps
    end

    add_index :campaigns, :active
  end
end
