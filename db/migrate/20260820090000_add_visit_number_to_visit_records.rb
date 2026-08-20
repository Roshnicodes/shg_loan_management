class AddVisitNumberToVisitRecords < ActiveRecord::Migration[8.1]
  def up
    add_column :visit_records, :visit_number, :integer, null: false, default: 1

    say_with_time "Backfilling visit numbers" do
      execute <<~SQL.squish
        WITH numbered_visits AS (
          SELECT
            id,
            ROW_NUMBER() OVER (
              PARTITION BY shg_member_id
              ORDER BY visit_date ASC, created_at ASC, id ASC
            ) AS calculated_visit_number
          FROM visit_records
        )
        UPDATE visit_records
        SET visit_number = numbered_visits.calculated_visit_number
        FROM numbered_visits
        WHERE visit_records.id = numbered_visits.id
      SQL
    end

    add_index :visit_records, [ :shg_member_id, :visit_number ], unique: true
  end

  def down
    remove_index :visit_records, [ :shg_member_id, :visit_number ]
    remove_column :visit_records, :visit_number
  end
end
