# Emails one approval notification through krai. A failed mail is logged and
# never affects the approval action that queued it.
class NotificationMailJob < ApplicationJob
  queue_as :default

  def perform(mail, kind = nil)
    return unless NotificationMailRelay.enabled?

    NotificationMailRelay.deliver!(mail, kind)
  rescue StandardError => error
    Rails.logger.error("NotificationMailRelay failed kind=#{kind} to=#{mail.to_h.stringify_keys['to_email']}: #{error.class} #{error.message}")
  end
end
