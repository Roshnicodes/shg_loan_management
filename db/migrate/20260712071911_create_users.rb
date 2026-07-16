class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :mobile
      t.string :designation
      t.references :user_type, null: false, foreign_key: true
      t.references :state, foreign_key: true
      t.references :district, foreign_key: true
      t.references :block, foreign_key: true
      t.references :village, foreign_key: true
      t.string :password_digest, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
