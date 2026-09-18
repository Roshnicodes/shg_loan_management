class BackfillConsistentShgReferences < ActiveRecord::Migration[8.1]
  def up
    sync_shg_locations_from_villages
    sync_loan_shgs_from_members
    sync_visit_shgs_from_members
  end

  def down
    # Data consistency repair only. Previous stale references cannot be inferred safely.
  end

  private

  def sync_shg_locations_from_villages
    execute <<~SQL.squish
      UPDATE shgs
      SET block_id = villages.block_id,
          district_id = blocks.district_id,
          state_id = districts.state_id,
          updated_at = CURRENT_TIMESTAMP
      FROM villages
      INNER JOIN blocks ON blocks.id = villages.block_id
      INNER JOIN districts ON districts.id = blocks.district_id
      WHERE shgs.village_id = villages.id
        AND (
          shgs.block_id IS DISTINCT FROM villages.block_id OR
          shgs.district_id IS DISTINCT FROM blocks.district_id OR
          shgs.state_id IS DISTINCT FROM districts.state_id
        )
    SQL
  end

  def sync_loan_shgs_from_members
    execute <<~SQL.squish
      UPDATE shg_loans
      SET shg_id = shg_members.shg_id,
          updated_at = CURRENT_TIMESTAMP
      FROM shg_members
      WHERE shg_loans.shg_member_id = shg_members.id
        AND shg_loans.shg_id IS DISTINCT FROM shg_members.shg_id
    SQL
  end

  def sync_visit_shgs_from_members
    execute <<~SQL.squish
      UPDATE visit_records
      SET shg_id = shg_members.shg_id,
          village_id = shgs.village_id,
          updated_at = CURRENT_TIMESTAMP
      FROM shg_members
      INNER JOIN shgs ON shgs.id = shg_members.shg_id
      WHERE visit_records.shg_member_id = shg_members.id
        AND (
          visit_records.shg_id IS DISTINCT FROM shg_members.shg_id OR
          visit_records.village_id IS DISTINCT FROM shgs.village_id
        )
    SQL
  end
end
