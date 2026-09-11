class AddShgMasterAndMemberFields < ActiveRecord::Migration[8.1]
  def up
    add_column :shgs, :office_location, :string unless column_exists?(:shgs, :office_location)
    add_column :shgs, :borrower_short_address, :text unless column_exists?(:shgs, :borrower_short_address)

    if column_exists?(:shg_members, :address)
      execute <<~SQL.squish
        UPDATE shgs
        SET borrower_short_address = source_addresses.address
        FROM (
          SELECT DISTINCT ON (shg_id) shg_id, address
          FROM shg_members
          WHERE address IS NOT NULL AND BTRIM(address) <> ''
          ORDER BY shg_id, id
        ) source_addresses
        WHERE shgs.id = source_addresses.shg_id
          AND (shgs.borrower_short_address IS NULL OR BTRIM(shgs.borrower_short_address) = '')
      SQL
    end

    add_reference :shg_members, :activity, foreign_key: true unless column_exists?(:shg_members, :activity_id)
    add_column :shg_members, :spouse_father_name, :string unless column_exists?(:shg_members, :spouse_father_name)
    add_column :shg_members, :aadhaar_no, :string unless column_exists?(:shg_members, :aadhaar_no)

    unless index_exists?(:shg_members, "LOWER(aadhaar_no)", name: "index_shg_members_on_unique_aadhaar_no")
      add_index :shg_members,
        "LOWER(aadhaar_no)",
        unique: true,
        where: "aadhaar_no IS NOT NULL AND BTRIM(aadhaar_no) <> ''",
        name: "index_shg_members_on_unique_aadhaar_no"
    end

    remove_column :shg_members, :address, :text if column_exists?(:shg_members, :address)
  end

  def down
    add_column :shg_members, :address, :text unless column_exists?(:shg_members, :address)

    remove_index :shg_members, name: "index_shg_members_on_unique_aadhaar_no" if index_exists?(:shg_members, name: "index_shg_members_on_unique_aadhaar_no")
    remove_column :shg_members, :aadhaar_no, :string if column_exists?(:shg_members, :aadhaar_no)
    remove_column :shg_members, :spouse_father_name, :string if column_exists?(:shg_members, :spouse_father_name)
    remove_reference :shg_members, :activity, foreign_key: true if column_exists?(:shg_members, :activity_id)
    remove_column :shgs, :borrower_short_address, :text if column_exists?(:shgs, :borrower_short_address)
    remove_column :shgs, :office_location, :string if column_exists?(:shgs, :office_location)
  end
end
