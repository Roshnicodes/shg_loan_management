class CreateUserTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :user_types do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :level, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
