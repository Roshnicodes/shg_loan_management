class CreateShgMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :shg_members do |t|
      t.references :shg, null: false, foreign_key: true
      t.references :member_type, null: false, foreign_key: true
      t.references :occupation, null: false, foreign_key: true
      t.string :name, null: false
      t.string :guardian_name
      t.string :gender
      t.date :dob
      t.string :mobile
      t.text :address
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
