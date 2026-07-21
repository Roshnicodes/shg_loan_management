class ShgMember < ApplicationRecord
  belongs_to :shg
  belongs_to :occupation
  has_many :shg_loans, dependent: :restrict_with_error
  has_many :visit_records, dependent: :restrict_with_error

  LOAN_NO_PREFIX = "ASAWO24".freeze

  before_validation :assign_loan_no, if: -> { loan_no.blank? }
  before_validation :normalize_contact_numbers

  validates :shg, :occupation, :gender, :dob, :mobile, :monthly_income, :address, presence: true
  validates :name, presence: true
  validates :loan_no, uniqueness: { allow_blank: true }
  validates :mobile, format: { with: /\A\d{10}\z/, allow_blank: true, message: "must be 10 digits" }
  validates :monthly_income, numericality: { greater_than_or_equal_to: 0, allow_blank: true }

  def display_name = "#{name} - #{shg.name}"

  private

  def normalize_contact_numbers
    self.mobile = mobile.to_s.gsub(/\D/, "") if mobile.present?
  end

  def assign_loan_no
    self.loan_no = "#{LOAN_NO_PREFIX}-#{next_loan_no_sequence}"
  end

  def next_loan_no_sequence
    last_number = self.class
      .where("loan_no LIKE ?", "#{LOAN_NO_PREFIX}-%")
      .pluck(:loan_no)
      .filter_map { |value| value.to_s.split("-").last.to_i if value.to_s.match?(/\A#{Regexp.escape(LOAN_NO_PREFIX)}-\d+\z/) }
      .max

    last_number.to_i + 1
  end
end
