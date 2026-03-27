class AddModeToCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :campaigns, :mode, :string, null: false, default: "outreach"
    add_index  :campaigns, :mode
  end
end
