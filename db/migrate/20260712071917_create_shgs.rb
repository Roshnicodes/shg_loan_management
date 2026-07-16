class CreateShgs < ActiveRecord::Migration[8.1]
  def change
    create_table :shgs do |t|
      t.references :state, null: false, foreign_key: true
      t.references :district, null: false, foreign_key: true
      t.references :block, null: false, foreign_key: true
      t.references :village, null: false, foreign_key: true
      t.string :name, null: false
      t.string :shg_code, null: false
      t.date :formation_date
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    add_index :shgs, :shg_code, unique: true
  end
end
