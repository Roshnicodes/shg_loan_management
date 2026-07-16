class RemoveMemberTypeAndGuardianFromShgMembers < ActiveRecord::Migration[8.1]
  def change
    remove_reference :shg_members, :member_type, foreign_key: true
    remove_column :shg_members, :guardian_name, :string
  end
end
