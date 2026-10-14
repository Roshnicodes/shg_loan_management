# Decides who gets an approval mail when an SHG or visit record moves through
# the approval flow, and queues one NotificationMailJob per person:
#
#   submitted / returned  -> District Coordinators of the SHG's district (or block)
#   approved by DC        -> Assistant Admins
#   returned              -> also the person who created the record
#   approved / rejected   -> the creator and the DC who approved it
#
# The person who took the action never gets a mail about it.
class ApprovalNotifier
  def self.silence
    previous = Thread.current[:approval_notifier_silenced]
    Thread.current[:approval_notifier_silenced] = true
    yield
  ensure
    Thread.current[:approval_notifier_silenced] = previous
  end

  def self.silenced?
    Thread.current[:approval_notifier_silenced] == true
  end

  def self.notify(record, event:, actor: nil, remark: nil)
    return if silenced? || !NotificationMailRelay.enabled?

    mails_for(record, event: event, actor: actor, remark: remark).each do |mail, kind|
      NotificationMailJob.perform_later(mail, kind)
    end
  rescue StandardError => error
    Rails.logger.error("ApprovalNotifier could not queue mails for #{record.class.name}##{record.id}: #{error.class} #{error.message}")
  end

  # [[mail, kind], ...] for one approval event.
  def self.mails_for(record, event:, actor: nil, remark: nil)
    label = record_label(record)
    form = record.is_a?(Shg) ? "SHG" : "Visit Record"
    by = actor ? " by #{actor.name}" : ""
    remark_text = remark.present? ? " Remark: #{remark}" : ""

    deliveries =
      case event
      when :submitted
        district_coordinators_for(record).map do |user|
          [ user, "approval_pending", "#{form} pending for your approval", "#{label} has been submitted#{by} and is waiting for your approval." ]
        end
      when :pending_assistant
        assistant_admins.map do |user|
          [ user, "approval_pending", "#{form} pending for your approval", "#{label} was approved#{by} (DC) and is waiting for your approval." ]
        end
      when :returned
        [ [ record.created_by, "approval_returned", "#{form} returned for correction", "#{label} was returned for correction#{by}.#{remark_text}" ] ] +
          district_coordinators_for(record).map do |user|
            [ user, "approval_pending", "#{form} pending for your approval", "#{label} was returned for correction#{by} and is pending for your action.#{remark_text}" ]
          end
      when :approved
        completion_users(record).map do |user|
          [ user, "approval_approved", "#{form} approved", "#{label} has been approved#{by}.#{remark_text}" ]
        end
      when :rejected
        completion_users(record).map do |user|
          [ user, "approval_rejected", "#{form} rejected", "#{label} was rejected#{by}.#{remark_text}" ]
        end
      else
        []
      end

    link = link_for(record)
    deliveries
      .select { |user, *| user.present? && user.active? && user.email.to_s.include?("@") && user.id != actor&.id }
      .uniq { |user, *| user.id }
      .map do |user, kind, subject, message|
        [ { "to_email" => user.email.to_s.strip, "to_name" => user.name.to_s, "subject" => subject, "message" => message, "link" => link }, kind ]
      end
  end

  def self.record_label(record)
    if record.is_a?(Shg)
      "SHG #{record.name} (#{record.shg_code})"
    else
      "#{record.visit_label} of #{record.shg_member&.name} (SHG #{record.shg&.name})"
    end
  end

  def self.shg_for(record)
    record.is_a?(Shg) ? record : record.shg
  end

  # Same rule as the DC's view of SHGs: their districts, or their blocks when
  # no district is mapped.
  def self.district_coordinators_for(record)
    shg = shg_for(record)
    return [] unless shg

    users_with_role_codes("DIST_COORDINATOR", "DISTRICT_COORDINATOR").select do |user|
      if user.office_district_ids.present?
        user.office_district_ids.include?(shg.district_id)
      else
        user.office_block_ids.include?(shg.block_id)
      end
    end
  end

  def self.assistant_admins
    users_with_role_codes("ASSIST_ADMIN", "ASSISTANT_ADMIN").to_a
  end

  def self.completion_users(record)
    [ record.created_by, record.dc_approved_by ]
  end

  def self.users_with_role_codes(*codes)
    User.joins(:user_type).where(active: true).where("UPPER(user_types.code) IN (?)", codes.map(&:upcase))
  end

  def self.link_for(record)
    options = NotificationMailRelay.link_url_options
    return "" unless options

    helpers = Rails.application.routes.url_helpers
    record.is_a?(Shg) ? helpers.shg_url(record, **options) : helpers.visit_record_url(record, **options)
  rescue StandardError
    ""
  end
end
