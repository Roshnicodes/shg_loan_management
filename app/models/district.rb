class District < ApplicationRecord
  include AutoCode

  belongs_to :state
  has_many :blocks, dependent: :restrict_with_error
  validates :name, :code, presence: true

  def display_name = name
end
