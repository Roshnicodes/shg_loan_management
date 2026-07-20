class User < ApplicationRecord
  has_secure_password

  belongs_to :user_type
  belongs_to :state, optional: true
  belongs_to :district, optional: true
  belongs_to :block, optional: true
  belongs_to :village, optional: true

  before_validation :normalize_login_id
  before_validation :normalize_mobile
  before_validation :normalize_office_mapping
  after_commit :attach_imported_crp_loans, on: %i[create update]

  validates :name, :email, :login_id, :mobile, :designation, :user_type, presence: true, if: :user_profile_validation_needed?
  validates :email, uniqueness: { case_sensitive: false, conditions: -> { where(active: true) } }, if: :active?
  validates :login_id, uniqueness: { case_sensitive: false, conditions: -> { where(active: true) } }, if: :active?
  validates :login_id, format: { with: /\A[a-zA-Z0-9_.-]+\z/, message: "can use only letters, numbers, dot, dash and underscore" }
  validates :mobile, format: { with: /\A\d{10}\z/, allow_blank: true, message: "must be 10 digits" }
  validates :password, length: { minimum: 6 }, if: -> { password.present? }
  validate :office_mapping_required, if: :office_mapping_validation_needed?

  def admin? = role_matches?("ADMIN")
  def assistant_admin? = role_matches?("ASSIST_ADMIN", "ASSISTANT_ADMIN")
  def district_coordinator? = role_matches?("DIST_COORDINATOR", "DISTRICT_COORDINATOR")
  def crp? = role_matches?("CRP")
  def approval_user? = assistant_admin? || district_coordinator?
  def entry_user? = crp? || assistant_admin? || district_coordinator?
  def readonly_admin? = false
  def display_name = "#{name} (#{user_type&.name})"

  def office_state_ids
    Array(state_id).compact
  end

  def office_district_ids
    normalize_id_list(mapped_district_ids) | Array(district_id).compact
  end

  def office_block_ids
    normalize_id_list(mapped_block_ids) | Array(block_id).compact
  end

  def office_village_ids
    normalize_id_list(mapped_village_ids) | Array(village_id).compact
  end

  def office_state_names
    State.where(id: office_state_ids).order(:name).pluck(:name)
  end

  def office_district_names
    District.where(id: office_district_ids).order(:name).pluck(:name)
  end

  def office_block_names
    Block.where(id: office_block_ids).order(:name).pluck(:name)
  end

  def office_village_names
    Village.where(id: office_village_ids).order(:name).pluck(:name)
  end

  private

  def attach_imported_crp_loans
    return unless crp? && login_id.present?

    ShgLoan.where("LOWER(source_crp_identifier) = ?", login_id.downcase)
      .where.not(created_by_id: id)
      .update_all(created_by_id: id, updated_at: Time.current)
  end

  def normalize_login_id
    self.login_id = login_id.to_s.strip.downcase
  end

  def normalize_mobile
    self.mobile = mobile.to_s.gsub(/\D/, "") if mobile.present?
  end

  def normalize_office_mapping
    self.mapped_district_ids = normalize_id_list(mapped_district_ids)
    self.mapped_block_ids = normalize_id_list(mapped_block_ids)
    self.mapped_village_ids = normalize_id_list(mapped_village_ids)

    if admin? || assistant_admin?
      self.district_id = nil
      self.block_id = nil
      self.village_id = nil
      self.mapped_district_ids = []
      self.mapped_block_ids = []
      self.mapped_village_ids = []
    elsif district_coordinator?
      self.mapped_district_ids = Array(mapped_district_ids.first || district_id).compact
      self.district_id = mapped_district_ids.first
      self.block_id = mapped_block_ids.first || block_id
      self.village_id = nil
      self.mapped_village_ids = []
    elsif crp?
      self.mapped_district_ids = Array(mapped_district_ids.first || district_id).compact
      self.mapped_block_ids = normalize_id_list(mapped_block_ids.presence || Array(block_id))
      self.mapped_village_ids = normalize_id_list(mapped_village_ids.presence || Array(village_id))
      self.district_id = mapped_district_ids.first
      self.block_id = mapped_block_ids.first || block_id
      self.village_id = mapped_village_ids.first || village_id
    end
  end

  def normalize_id_list(values)
    Array(values).reject(&:blank?).map(&:to_i).reject(&:zero?).uniq
  end

  def user_profile_validation_needed?
    new_record? ||
      will_save_change_to_name? ||
      will_save_change_to_email? ||
      will_save_change_to_login_id? ||
      will_save_change_to_mobile? ||
      will_save_change_to_designation? ||
      will_save_change_to_user_type_id? ||
      office_mapping_validation_needed?
  end

  def office_mapping_validation_needed?
    new_record? ||
      will_save_change_to_user_type_id? ||
      will_save_change_to_state_id? ||
      will_save_change_to_district_id? ||
      will_save_change_to_block_id? ||
      will_save_change_to_village_id? ||
      will_save_change_to_mapped_district_ids? ||
      will_save_change_to_mapped_block_ids? ||
      will_save_change_to_mapped_village_ids? ||
      (will_save_change_to_active? && active?)
  end

  def office_mapping_required
    return if user_type.blank?

    errors.add(:state, "office is required") if state_id.blank?
    errors.add(:district, "office is required") if (district_coordinator? || crp?) && office_district_ids.blank?
  end

  def role_matches?(*keys)
    normalized_keys = keys.map { |key| key.to_s.upcase }
    normalized_keys.include?(role_code) || normalized_keys.include?(role_name_key)
  end

  def role_code
    user_type&.code.to_s.upcase
  end

  def role_name_key
    user_type&.name.to_s.parameterize(separator: "_").upcase
  end
end
