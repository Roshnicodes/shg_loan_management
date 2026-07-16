class MakeNewShgsDraft < ActiveRecord::Migration[8.1]
  def change
    change_column_default :shgs, :approval_status, from: "pending_dc", to: "draft"
  end
end
