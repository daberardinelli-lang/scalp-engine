class AddCampaignIdToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_reference :companies, :campaign, null: true, foreign_key: true
  end
end
