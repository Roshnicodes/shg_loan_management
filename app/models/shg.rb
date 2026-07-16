class Shg < ApplicationRecord
  belongs_to :state
  belongs_to :district
  belongs_to :block
  belongs_to :village
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :dc_approved_by, class_name: "User", optional: true
  belongs_to :assistant_approved_by, class_name: "User", optional: true
  has_many :shg_members, dependent: :destroy
  has_many :shg_loans, dependent: :restrict_with_error
  has_many :visit_records, dependent: :restrict_with_error
  has_one_attached :meeting_register
  has_one_attached :meeting_photo

  APPROVAL_STATUSES = [ "draft", "pending_dc", "pending_assistant", "approved", "rejected" ].freeze

  before_validation :build_shg_code, if: -> { shg_code.blank? && name.present? }
  before_validation :set_default_approval_status

  validates :name, :shg_code, presence: true
  validates :shg_code, uniqueness: true
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validate :meeting_register_file_type
  validate :meeting_photo_file_type
  validate :meeting_register_file_size
  validate :meeting_photo_file_size

  def display_name = name
  def draft? = approval_status == "draft"
  def pending_approval? = pending_dc? || pending_assistant?
  def pending_dc? = approval_status == "pending_dc"
  def pending_assistant? = approval_status == "pending_assistant"
  def approved? = approval_status == "approved"
  def approval_label = approval_status.to_s.titleize

  def ready_for_approval?
    shg_members.exists? && shg_loans.exists?
  end

  def submit_for_approval!(user = nil)
    return false unless draft?
    return false unless ready_for_approval?

    actor = user || created_by
    timestamp = Time.current

    if actor&.assistant_admin?
      update!(
        approval_status: "approved",
        assistant_approved_by: actor,
        assistant_approved_at: timestamp,
        approved_by: actor,
        approved_at: timestamp
      )
    elsif actor&.district_coordinator?
      update!(
        approval_status: "pending_assistant",
        dc_approved_by: actor,
        dc_approved_at: timestamp
      )
    else
      update!(
        approval_status: "pending_dc",
        dc_approved_by: nil,
        dc_approved_at: nil,
        assistant_approved_by: nil,
        assistant_approved_at: nil,
        approved_by: nil,
        approved_at: nil
      )
    end
  end

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

  def set_default_approval_status
    self.approval_status ||= "draft"
  end

  def build_shg_code
    prefix = [ state&.code, district&.code, block&.code, village&.code ]
      .compact_blank
      .join("-")
      .upcase
    clean_name = name.to_s.parameterize(separator: "").upcase.first(8)
    base = [ prefix, clean_name ].compact_blank.join("-")
    self.shg_code = base
    return unless Shg.exists?(shg_code: shg_code)

    self.shg_code = "#{base}-#{Time.current.strftime('%H%M%S')}"
  end

  def meeting_register_file_type
    return unless meeting_register.attached?

    allowed_types = %w[application/pdf image/jpeg image/png image/webp]
    return if allowed_types.include?(meeting_register.blob.content_type)

    errors.add(:meeting_register, "must be PDF, JPG, PNG or WEBP")
  end

  def meeting_photo_file_type
    return unless meeting_photo.attached?

    allowed_types = %w[application/pdf image/jpeg image/png image/webp]
    return if allowed_types.include?(meeting_photo.blob.content_type)

    errors.add(:meeting_photo, "must be PDF, JPG, PNG or WEBP")
  end

  def meeting_register_file_size
    validate_attachment_size(meeting_register, :meeting_register)
  end

  def meeting_photo_file_size
    validate_attachment_size(meeting_photo, :meeting_photo)
  end

  def validate_attachment_size(attachment, field)
    return unless attachment.attached?
    return if attachment.blob.byte_size <= 5.megabytes

    errors.add(field, "must be 5 MB or smaller")
  end
end
