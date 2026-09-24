class ShgMember < ApplicationRecord
  belongs_to :shg
  belongs_to :occupation
  belongs_to :activity, optional: true
  has_many :shg_loans, dependent: :restrict_with_error
  has_many :visit_records, dependent: :restrict_with_error

  LOAN_NO_PREFIX = "ASAWO26".freeze

  before_validation :normalize_work_activity
  before_validation :normalize_contact_numbers
  before_validation :normalize_aadhaar_no
  after_update :sync_dependent_group_references, if: :saved_change_to_shg_id?

  validates :shg, :occupation, :gender, :dob, :mobile, :monthly_income, presence: true
  validates :name, presence: true
  validates :loan_no, uniqueness: { allow_blank: true }
  validates :mobile, format: { with: /\A\d{10}\z/, allow_blank: true, message: "must be 10 digits" }
  validates :aadhaar_no, format: { with: /\A\d{12}\z/, allow_blank: true, message: "must be 12 digits" }
  validates :monthly_income, numericality: { greater_than_or_equal_to: 0, allow_blank: true }
  validate :aadhaar_no_not_duplicated

  def display_name = "#{name} - #{shg.name}"

  def work_activity
    has_attribute?(:work_activity) ? self[:work_activity] : @work_activity
  end

  def work_activity=(value)
    if has_attribute?(:work_activity)
      self[:work_activity] = value
    else
      @work_activity = value
    end
  end

  def work_activity_name = work_activity.presence || activity&.name

  def assign_next_loan_no!
    return loan_no if loan_no.present?

    attempts = 0
    with_lock do
      reload
      return loan_no if loan_no.present?

      update_columns(loan_no: self.class.next_loan_no, updated_at: Time.current)
      loan_no
    end
  rescue ActiveRecord::RecordNotUnique
    attempts += 1
    retry if attempts < 3

    raise
  end

  def self.next_loan_no
    "#{LOAN_NO_PREFIX}-#{next_loan_no_sequence.to_s.rjust(2, '0')}"
  end

  def self.assign_missing_loan_numbers_for_active_loans(member_ids = nil)
    members = where(active: true, loan_no: [ nil, "" ])
    members = members.where(id: member_ids) if member_ids
    members = members.where(id: ShgLoan.joins(:shg_member).where(active: true, shg_members: { active: true }).select(:shg_member_id))

    members.order(:id).find_each(&:assign_next_loan_no!)
  end

  def self.clear_stale_loan_numbers_without_loans!(member_ids = nil)
    members = where.not(loan_no: [ nil, "" ])
    members = members.where(id: member_ids) if member_ids.present?

    members.left_outer_joins(:shg_loans)
      .where(shg_loans: { id: nil })
      .update_all(loan_no: nil, updated_at: Time.current)
  end

  def clear_stale_loan_number_without_loans!
    self.class.clear_stale_loan_numbers_without_loans!(id)
  end

  def self.next_loan_no_sequence
    expected_sequence = 1

    existing_loan_no_sequences.each do |sequence|
      next if sequence < expected_sequence
      return expected_sequence if sequence > expected_sequence

      expected_sequence += 1
    end

    expected_sequence
  end

  def self.existing_loan_no_sequences
    where("loan_no LIKE ?", "#{LOAN_NO_PREFIX}-%")
      .pluck(:loan_no)
      .filter_map { |value| value.to_s.split("-").last.to_i if value.to_s.match?(/\A#{Regexp.escape(LOAN_NO_PREFIX)}-\d+\z/) }
      .sort
  end

  private

  def normalize_work_activity
    self.work_activity = work_activity.to_s.squish.presence if has_attribute?(:work_activity)
  end

  def normalize_contact_numbers
    self.mobile = mobile.to_s.gsub(/\D/, "") if mobile.present?
  end

  def normalize_aadhaar_no
    self.aadhaar_no = aadhaar_no.to_s.gsub(/\D/, "") if aadhaar_no.present?
  end

  def aadhaar_no_not_duplicated
    return if aadhaar_no.blank?

    duplicate = self.class.where("LOWER(aadhaar_no) = ?", aadhaar_no.downcase).where.not(id: id).includes(:shg).first
    return unless duplicate

    errors.add(:aadhaar_no, "is already used by #{duplicate.name} in #{duplicate.shg&.name}")
  end

  def sync_dependent_group_references
    current_shg = shg || Shg.find_by(id: shg_id)
    return unless current_shg

    timestamp = Time.current
    ShgLoan.where(shg_member_id: id).where.not(shg_id: current_shg.id).update_all(shg_id: current_shg.id, updated_at: timestamp)
    VisitRecord.where(shg_member_id: id).where.not(shg_id: current_shg.id).update_all(shg_id: current_shg.id, village_id: current_shg.village_id, updated_at: timestamp)
    VisitRecord.where(shg_member_id: id, shg_id: current_shg.id).where.not(village_id: current_shg.village_id).update_all(village_id: current_shg.village_id, updated_at: timestamp)
  end
end
