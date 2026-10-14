# Mails the next approver (and the creator on return/approve/reject) whenever
# an SHG or visit record changes approval status. See ApprovalNotifier.
module ApprovalNotifications
  extend ActiveSupport::Concern

  included do
    # Who took the approval action, and whether it was a return for correction.
    # Only used while saving; not stored.
    attr_accessor :approval_actor, :approval_returned

    after_commit :send_approval_notifications, on: %i[create update]
  end

  private

  def send_approval_notifications
    returned = approval_returned
    self.approval_returned = false
    return unless returned || saved_change_to_approval_status?

    event =
      if returned
        :returned
      else
        { "pending_dc" => :submitted, "pending_assistant" => :pending_assistant, "approved" => :approved, "rejected" => :rejected }[approval_status]
      end
    return unless event

    actor = approval_actor || default_approval_actor(event)
    remark = approval_remarks if %i[returned rejected].include?(event)
    ApprovalNotifier.notify(self, event: event, actor: actor, remark: remark)
  end

  def default_approval_actor(event)
    case event
    when :pending_assistant then dc_approved_by
    when :approved, :rejected then approved_by
    else created_by
    end
  end
end
