class District < ApplicationRecord
  include AutoCode

  belongs_to :state
  has_many :blocks, dependent: :restrict_with_error
  after_update :sync_shg_state_references, if: :saved_change_to_state_id?

  validates :name, :code, presence: true

  def display_name = name

  private

  def sync_shg_state_references
    Shg.where(district_id: id).where.not(state_id: state_id).update_all(state_id: state_id, updated_at: Time.current)
  end
end
