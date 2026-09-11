class AddWorkActivityToShgMembers < ActiveRecord::Migration[8.1]
  def up
    add_column :shg_members, :work_activity, :string unless column_exists?(:shg_members, :work_activity)

    execute <<~SQL.squish
      UPDATE shg_members
      SET work_activity = activities.name
      FROM activities
      WHERE shg_members.activity_id = activities.id
        AND (shg_members.work_activity IS NULL OR BTRIM(shg_members.work_activity) = '')
    SQL
  end

  def down
    remove_column :shg_members, :work_activity, :string if column_exists?(:shg_members, :work_activity)
  end
end
