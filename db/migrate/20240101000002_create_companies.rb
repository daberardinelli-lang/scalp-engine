class CreateCompanies < ActiveRecord::Migration[8.0]
  def change
    create_table :companies do |t|
      # Dati base
      t.string  :name,         null: false
      t.string  :category,     null: false  # restaurant / plumber / retail / lawyer / etc.
      t.string  :address
      t.string  :city
      t.string  :province
      t.string  :phone

      # Google Places
      t.string  :google_place_id, index: { unique: true }
      t.decimal :maps_rating,        precision: 2, scale: 1
      t.integer :maps_reviews_count, default: 0
      t.boolean :has_website,        default: false, null: false
      t.string  :maps_photo_urls,    array: true, default: []  # PostgreSQL array

      # Contatto
      t.string  :email
      t.string  :email_source   # google / facebook / instagram / paginegialle / manual
      t.string  :email_status,  default: "unknown"  # found / manual / skip / unknown

      # Stato pipeline
      t.string  :status, default: "discovered", null: false
      # discovered → enriched → demo_built → contacted → replied → converted / opted_out

      # GDPR
      t.datetime :opted_out_at

      # Soft delete
      t.datetime :discarded_at

      t.text    :notes
      t.timestamps
    end

    add_index :companies, :status
    add_index :companies, :category
    add_index :companies, :province
    add_index :companies, :discarded_at
    add_index :companies, :opted_out_at
  end
end
