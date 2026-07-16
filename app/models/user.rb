class User < ApplicationRecord
  has_secure_password

  belongs_to :user_type
  belongs_to :state, optional: true
  belongs_to :district, optional: true
  belongs_to :block, optional: true
  belongs_to :village, optional: true

  before_validation :normalize_login_id
  before_validation :normalize_mobile

  validates :name, :email, :login_id, presence: true
  validates :email, uniqueness: true
  validates :login_id, uniqueness: { case_sensitive: false }, format: { with: /\A[a-zA-Z0-9_.-]+\z/, message: "can use only letters, numbers, dot, dash and underscore" }
  validates :mobile, format: { with: /\A\d{10}\z/, allow_blank: true, message: "must be 10 digits" }
  validates :password, length: { minimum: 6 }, if: -> { password.present? }

  def admin? = role_matches?("ADMIN")
  def assistant_admin? = role_matches?("ASSIST_ADMIN", "ASSISTANT_ADMIN")
  def district_coordinator? = role_matches?("DIST_COORDINATOR", "DISTRICT_COORDINATOR")
  def crp? = role_matches?("CRP")
  def approval_user? = assistant_admin? || district_coordinator?
  def entry_user? = crp? || assistant_admin? || district_coordinator?
  def readonly_admin? = false
  def display_name = "#{name} (#{user_type&.name})"

  private

  def normalize_login_id
    self.login_id = login_id.to_s.strip.downcase
  end

  def normalize_mobile
    self.mobile = mobile.to_s.gsub(/\D/, "") if mobile.present?
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
