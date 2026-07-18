class AddMultiOfficeMappingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mapped_district_ids, :integer, array: true, default: [], null: false
    add_column :users, :mapped_block_ids, :integer, array: true, default: [], null: false
    add_column :users, :mapped_village_ids, :integer, array: true, default: [], null: false
  end
end
