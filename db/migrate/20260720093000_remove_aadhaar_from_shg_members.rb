class RemoveAadhaarFromShgMembers < ActiveRecord::Migration[8.1]
  def change
    remove_index :shg_members, :aadhaar_no if index_exists?(:shg_members, :aadhaar_no)
    remove_column :shg_members, :aadhaar_no, :string if column_exists?(:shg_members, :aadhaar_no)
  end
end
