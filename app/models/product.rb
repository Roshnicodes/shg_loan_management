class Product < ApplicationRecord
  include AutoCode

  validates :name, :code, presence: true
  validates :code, uniqueness: true

  def display_name
    [ code.presence, name ].compact_blank.join(" - ")
  end
end
