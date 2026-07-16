class AddImportLookupIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :states, :name
    add_index :districts, [ :state_id, :name ]
    add_index :blocks, [ :district_id, :name ]
    add_index :villages, [ :block_id, :name ]
    add_index :shgs, [ :village_id, :name ]
    add_index :shg_members, [ :shg_id, :name ]
    add_index :products, :name
    add_index :activities, :name
    add_index :occupations, :name
    add_index :loan_statuses, :code
    add_index :loan_statuses, :name
    add_index :users, :name
  end
end
