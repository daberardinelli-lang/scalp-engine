class AddEnrichmentFieldsToCompanies < ActiveRecord::Migration[8.0]
  def change
    # Recensioni Google Maps (array di oggetti jsonb)
    # Struttura: [{author:, rating:, text:, date:}, ...]
    add_column :companies, :reviews_data, :jsonb, default: []

    # Sorgente da cui è stata trovata l'email (paginegialle / facebook / manual)
    # Già presente: email_source string → nessuna modifica necessaria

    # Timestamp ultimo arricchimento (utile per re-enrich periodico)
    add_column :companies, :enriched_at, :datetime

    add_index :companies, :enriched_at
  end
end
