class CreateDistricts < ActiveRecord::Migration[8.1]
  def change
    create_table :districts do |t|
      t.references :state, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
