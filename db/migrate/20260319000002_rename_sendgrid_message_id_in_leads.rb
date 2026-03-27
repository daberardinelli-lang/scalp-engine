class RenameSendgridMessageIdInLeads < ActiveRecord::Migration[8.0]
  def change
    rename_column :leads, :sendgrid_message_id, :provider_message_id
  end
end
