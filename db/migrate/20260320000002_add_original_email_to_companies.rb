class AddOriginalEmailToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :original_email, :string
  end
end
