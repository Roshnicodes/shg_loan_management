class CreateDataExports < ActiveRecord::Migration[8.1]
  def change
    create_table :data_exports do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :status, null: false, default: "queued"
      t.jsonb :filter_params, null: false, default: {}
      t.string :request_host
      t.string :request_protocol
      t.string :filename
      t.string :file_path
      t.integer :total_rows, null: false, default: 0
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :data_exports, %i[user_id created_at]
  end
end
