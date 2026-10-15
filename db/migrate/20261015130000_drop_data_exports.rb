# Downloads are streamed directly again, so the background export list is gone.
class DropDataExports < ActiveRecord::Migration[8.1]
  def change
    drop_table :data_exports do |t|
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
      t.index %i[user_id created_at]
    end
  end
end
