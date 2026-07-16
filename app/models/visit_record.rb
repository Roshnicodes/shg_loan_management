class VisitRecord < ApplicationRecord
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

  validates :visit_date, presence: true
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validate :member_belongs_to_shg
  validate :shg_belongs_to_village
  validate :photo_file_type
  validate :photo_file_size

  def pending_dc? = approval_status == "pending_dc"
  def pending_assistant? = approval_status == "pending_assistant"
  def approved? = approval_status == "approved"
  def approval_label = approval_status.to_s.titleize

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

  private

  def set_default_status
    if created_by&.assistant_admin?
      self.approval_status = "approved"
      self.assistant_approved_by = created_by
      self.assistant_approved_at = Time.current
      self.approved_by = created_by
      self.approved_at = Time.current
    elsif created_by&.district_coordinator?
      self.approval_status = "pending_assistant"
      self.dc_approved_by = created_by
      self.dc_approved_at = Time.current
    else
      self.approval_status ||= "pending_dc"
    end
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
