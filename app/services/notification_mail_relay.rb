require "json"
require "net/http"
require "uri"

# Sends approval notification mails through the ASA mail service (krai), the
# same way Apurti does, because the server has no SMTP:
#
#   GET https://krai.asaindia.org/wash360_nnotify.aspx?to_email=...&to_name=...&subject=...&message=...&link=...
#
# NOTIFICATION_MAIL_RELAY_URL is krai's address (https://krai.asaindia.org/) or
# a full page address (…/x.aspx). One kind can get its own page with
# NOTIFICATION_MAIL_PAGE_<KIND>, e.g. NOTIFICATION_MAIL_PAGE_APPROVAL_PENDING=x.aspx.
# NOTIFICATION_MAIL_APP_URL (e.g. https://shg.example.org) is used for the
# record link in the mail.
#
# Off until NOTIFICATION_MAIL_RELAY_URL is set, so nothing changes before krai
# provides the page.
class NotificationMailRelay
  class DeliveryError < StandardError; end

  FIELDS = %w[to_email to_name subject message link].freeze

  # Kinds set in ApprovalNotifier.
  KINDS = %w[
    approval_pending
    approval_returned
    approval_approved
    approval_rejected
  ].freeze
  DEFAULT_PAGE = "wash360_nnotify.aspx".freeze
  TIMEOUT_SECONDS = 15
  MAX_REDIRECTS = 3

  def self.url
    ENV["NOTIFICATION_MAIL_RELAY_URL"].to_s.strip
  end

  def self.enabled?
    url.present?
  end

  # Full krai address for one kind of notification.
  def self.page_url(kind)
    base = URI.parse(url)
    own_page = kind.present? ? ENV["NOTIFICATION_MAIL_PAGE_#{kind.to_s.upcase}"].to_s.strip.presence : nil
    return base.to_s if own_page.nil? && base.path.to_s.end_with?(".aspx")

    page = own_page || DEFAULT_PAGE
    URI.join(base.to_s.end_with?("/") || base.path.to_s.end_with?(".aspx") ? base.to_s : "#{base}/", page).to_s
  end

  def self.link_url_options
    base = ENV["NOTIFICATION_MAIL_APP_URL"].presence
    return nil if base.blank?

    uri = URI.parse(base)
    { host: uri.host, protocol: uri.scheme, port: uri.port == uri.default_port ? nil : uri.port }.compact
  end

  def self.request_uri(mail, kind)
    uri = URI.parse(page_url(kind))
    uri.query = URI.encode_www_form(mail.stringify_keys.slice(*FIELDS).transform_values(&:to_s))
    uri
  end

  def self.deliver!(mail, kind)
    mail = mail.stringify_keys
    return false unless mail["to_email"].to_s.include?("@")

    response, final_uri = fetch(request_uri(mail, kind))
    where = "[#{final_uri.scheme}://#{final_uri.host}#{final_uri.path}]"
    raise DeliveryError, "Mail service asked for a login #{where}" if login_page?(final_uri)
    raise DeliveryError, "#{failure_message(response)} #{where}" unless success?(response)

    Rails.logger.info("NotificationMailRelay sent kind=#{kind} to=#{mail['to_email']} status=#{response.code}")
    true
  end

  # krai's page may answer with a redirect (302 "Object moved") to a result
  # page; follow it and judge the page it ends on.
  def self.fetch(uri)
    response = get(uri)
    MAX_REDIRECTS.times do
      break unless response.is_a?(Net::HTTPRedirection) && response["location"].present?

      uri = URI.join(uri.to_s, response["location"])
      response = get(uri)
    end
    [ response, uri ]
  end

  def self.get(uri)
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Accept"] = "application/json"

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
      http.request(request)
    end
  end

  def self.login_page?(uri)
    uri.path.to_s.downcase.match?(/login|signin|sign_in/)
  end

  # A 2xx answer is a success unless its JSON says otherwise
  # ("success": false, or "status": "error"/"failed").
  def self.success?(response)
    return false unless response.is_a?(Net::HTTPSuccess)

    body = parsed_body(response)
    return true unless body.is_a?(Hash)
    return false if body.key?("success") && !ActiveModel::Type::Boolean.new.cast(body["success"])

    !body["status"].to_s.downcase.in?(%w[error failed failure])
  end

  def self.failure_message(response)
    body = parsed_body(response)
    detail = body["message"] || body["error"] if body.is_a?(Hash)
    detail ||= response.body.to_s.gsub(/<[^>]+>/, " ").squish.first(160)
    "Mail service returned #{response.code}: #{detail.presence || response.message}"
  end

  def self.parsed_body(response)
    JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    nil
  end
end
