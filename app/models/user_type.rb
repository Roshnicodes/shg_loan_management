class UserType < ApplicationRecord
  include AutoCode

  LEVELS = [ "state", "district", "block", "village" ].freeze
  validates :name, :code, :level, presence: true
  validates :code, uniqueness: true
  validates :level, inclusion: { in: LEVELS }

  def display_name = "#{name} - #{level.titleize}"
end
