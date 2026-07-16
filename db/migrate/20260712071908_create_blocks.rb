class CreateBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :blocks do |t|
      t.references :district, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
