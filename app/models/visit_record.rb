class VisitRecord < ApplicationRecord
  attr_writer :block_id

  belongs_to :village
  belongs_to :shg
  belongs_to :shg_member
  belongs_to :product, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :dc_approved_by, class_name: "User", optional: true
  belongs_to :assistant_approved_by, class_name: "User", optional: true

  has_one_attached :photo

  APPROVAL_STATUSES = [ "pending_dc", "pending_assistant", "approved", "rejected" ].freeze

  before_validation :set_default_status, on: :create
  before_validation :set_product_from_member_loan, if: -> { product.blank? && shg_member.present? }
  before_validation :set_visit_number, on: :create

  validates :visit_date, presence: true
  validates :visit_number, numericality: { only_integer: true, greater_than: 0 }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validate :member_belongs_to_shg
  validate :shg_belongs_to_village
  validate :photo_file_type
  validate :photo_file_size

  scope :duplicate_of, ->(visit) {
    where(
      active: true,
      shg_member_id: visit.shg_member_id
    ).order(visit_number: :desc, visit_date: :desc, updated_at: :desc, id: :desc)
  }

  def pending_dc? = approval_status == "pending_dc"
  def pending_assistant? = approval_status == "pending_assistant"
  def approved? = approval_status == "approved"
  def approval_label = approval_status.to_s.titleize
  def block_id = @block_id.presence || village&.block_id || shg&.block_id
  def visit_label = "Visit #{visit_number}"

  def approve!(user)
    raise ActiveRecord::RecordInvalid, self unless approvable_by?(user)

    if user.district_coordinator?
      update!(
        approval_status: "pending_assistant",
        dc_approved_by: user,
        dc_approved_at: Time.current
      )
    else
      update!(
        approval_status: "approved",
        assistant_approved_by: user,
        assistant_approved_at: Time.current,
        approved_by: user,
        approved_at: Time.current
      )
    end
  end

  def reject!(user, remarks = nil)
    raise ActiveRecord::RecordInvalid, self unless rejectable_by?(user)

    update!(approval_status: "rejected", approved_by: user, approved_at: Time.current, approval_remarks: remarks)
  end

  def return_for_correction!(user, remarks = nil)
    raise ActiveRecord::RecordInvalid, self unless returnable_by?(user)

    update!(
      approval_status: "pending_dc",
      dc_approved_by: nil,
      dc_approved_at: nil,
      assistant_approved_by: nil,
      assistant_approved_at: nil,
      approved_by: nil,
      approved_at: nil,
      approval_remarks: remarks.presence || "Returned for correction"
    )
  end

  def approvable_by?(user)
    return false unless user

    (pending_dc? && user.district_coordinator?) ||
      (pending_assistant? && user.assistant_admin?)
  end

  def rejectable_by?(user)
    approvable_by?(user)
  end

  def returnable_by?(user)
    approvable_by?(user)
  end

  def merge_submission!(submitted_visit, user)
    increment_visit_number = visit_date != submitted_visit.visit_date || product_id != submitted_visit.product_id

    assign_attributes(
      village: submitted_visit.village,
      shg: submitted_visit.shg,
      shg_member: submitted_visit.shg_member,
      product: submitted_visit.product,
      visit_date: submitted_visit.visit_date,
      purpose: submitted_visit.purpose,
      observations: submitted_visit.observations,
      active: true,
      created_by: user
    )
    self.visit_number = visit_number.to_i + 1 if increment_visit_number
    apply_default_status_for(user)
    save!
  end

  private

  def set_default_status
    apply_default_status_for(created_by)
  end

  def apply_default_status_for(user)
    if user&.assistant_admin?
      self.approval_status = "approved"
      self.dc_approved_by = nil
      self.dc_approved_at = nil
      self.assistant_approved_by = user
      self.assistant_approved_at = Time.current
      self.approved_by = user
      self.approved_at = Time.current
    elsif user&.district_coordinator?
      self.approval_status = "pending_assistant"
      self.dc_approved_by = user
      self.dc_approved_at = Time.current
      self.assistant_approved_by = nil
      self.assistant_approved_at = nil
      self.approved_by = nil
      self.approved_at = nil
    else
      self.approval_status = "pending_dc"
      self.dc_approved_by = nil
      self.dc_approved_at = nil
      self.assistant_approved_by = nil
      self.assistant_approved_at = nil
      self.approved_by = nil
      self.approved_at = nil
    end
  end

  def set_product_from_member_loan
    self.product = shg_member.shg_loans.order(active: :desc, id: :asc).first&.product
  end

  def set_visit_number
    return if shg_member_id.blank?
    return if visit_number.present? && !(visit_number == 1 && self.class.where(shg_member_id: shg_member_id).exists?)

    self.visit_number = self.class.where(shg_member_id: shg_member_id).maximum(:visit_number).to_i + 1
  end

  def member_belongs_to_shg
    return if shg_member.blank? || shg.blank? || shg_member.shg_id == shg.id

    errors.add(:shg_member, "must belong to selected SHG")
  end

  def shg_belongs_to_village
    return if shg.blank? || village.blank? || shg.village_id == village.id

    errors.add(:shg, "must belong to selected village")
  end

  def photo_file_type
    return unless photo.attached?

    allowed_types = %w[application/pdf image/jpeg image/png image/webp]
    return if allowed_types.include?(photo.blob.content_type)

    errors.add(:photo, "must be PDF, JPG, PNG or WEBP")
  end

  def photo_file_size
    return unless photo.attached?
    return if photo.blob.byte_size <= 5.megabytes

    errors.add(:photo, "must be 5 MB or smaller")
  end
end
