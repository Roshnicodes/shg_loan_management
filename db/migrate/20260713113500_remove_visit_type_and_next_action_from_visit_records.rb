class RemoveVisitTypeAndNextActionFromVisitRecords < ActiveRecord::Migration[8.1]
  def change
    remove_column :visit_records, :visit_type, :string
    remove_column :visit_records, :next_action, :text
  end
end
