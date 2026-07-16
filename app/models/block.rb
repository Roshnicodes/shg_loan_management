class Block < ApplicationRecord
  include AutoCode

  belongs_to :district
  has_many :villages, dependent: :restrict_with_error
  validates :name, :code, presence: true

  def display_name = name
end
