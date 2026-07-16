class DropMemberTypes < ActiveRecord::Migration[8.1]
  def change
    drop_table :member_types do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
  end
end
