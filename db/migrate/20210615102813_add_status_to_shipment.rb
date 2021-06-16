class AddStatusToShipment < ActiveRecord::Migration[6.1]
  def change
    add_column :shipments, :status, :string, default: 'pending'
  end
end
