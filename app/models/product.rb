class Product < ApplicationRecord
  include AutoCode

  validates :name, :code, presence: true
  validates :code, uniqueness: true
end
