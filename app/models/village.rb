class Village < ApplicationRecord
  include AutoCode

  belongs_to :block
  validates :name, :code, presence: true

  def display_name = name
end
