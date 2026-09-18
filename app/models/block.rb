class Block < ApplicationRecord
  include AutoCode

  belongs_to :district
  has_many :villages, dependent: :restrict_with_error
  after_update :sync_shg_location_references, if: :saved_change_to_district_id?

  validates :name, :code, presence: true

  def display_name = name

  private

  def sync_shg_location_references
    Shg.where(block_id: id).update_all(district_id: district_id, state_id: district.state_id, updated_at: Time.current)
  end
end
