class Village < ApplicationRecord
  include AutoCode

  belongs_to :block
  after_update :sync_shg_location_references, if: :saved_change_to_block_id?

  validates :name, :code, presence: true

  def display_name = name

  private

  def sync_shg_location_references
    Shg.where(village_id: id).update_all(block_id: block_id, district_id: block.district_id, state_id: block.district.state_id, updated_at: Time.current)
  end
end
