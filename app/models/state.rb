class State < ApplicationRecord
  include AutoCode

  has_many :districts, dependent: :restrict_with_error
  validates :name, :code, presence: true
  validates :code, uniqueness: true

  def display_name = name
end
