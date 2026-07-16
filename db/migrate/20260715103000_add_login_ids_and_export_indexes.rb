class AddLoginIdsAndExportIndexes < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :login_id, :string

    User.reset_column_information
    User.find_each do |user|
      user.update_columns(login_id: user.id.to_s)
    end

    change_column_null :users, :login_id, false
    add_index :users, :login_id, unique: true

    add_index :shg_loans, :distribution_date unless index_exists?(:shg_loans, :distribution_date)
    add_index :shgs, :approval_status unless index_exists?(:shgs, :approval_status)
    add_index :visit_records, :visit_date unless index_exists?(:visit_records, :visit_date)
    add_index :visit_records, :approval_status unless index_exists?(:visit_records, :approval_status)
  end

  def down
    remove_index :visit_records, :approval_status if index_exists?(:visit_records, :approval_status)
    remove_index :visit_records, :visit_date if index_exists?(:visit_records, :visit_date)
    remove_index :shgs, :approval_status if index_exists?(:shgs, :approval_status)
    remove_index :shg_loans, :distribution_date if index_exists?(:shg_loans, :distribution_date)
    remove_index :users, :login_id if index_exists?(:users, :login_id)
    remove_column :users, :login_id
  end
end
