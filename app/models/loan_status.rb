class LoanStatus < ApplicationRecord
  include AutoCode

  validates :name, :code, presence: true
  validates :code, uniqueness: true

  def self.default_active = find_by(code: "ACTIVE") || first
end
