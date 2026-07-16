class CreateMemberTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :member_types do |t|
      t.string :name, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
