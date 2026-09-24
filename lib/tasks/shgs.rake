require "csv"

namespace :shgs do
  desc "Preview draft SHGs that are ready to be sent for approval"
  task preview_ready_drafts: :environment do
    shgs = ready_draft_shgs
    puts ready_draft_shgs_csv(shgs)
    puts "Ready drafts: #{shgs.size}"
    puts "No data changed. Run shgs:submit_ready_drafts CONFIRM=YES only after reviewing this list."
  end

  desc "Submit ready draft SHGs to the normal approval flow. Requires CONFIRM=YES"
  task submit_ready_drafts: :environment do
    unless ENV["CONFIRM"] == "YES"
      abort "Refusing to change SHG approvals. First run shgs:preview_ready_drafts, then rerun with CONFIRM=YES."
    end

    submitted = 0
    ready_draft_shgs.find_each do |shg|
      submitted += 1 if shg.submit_for_approval_if_ready!
    end

    puts "Submitted: #{submitted}"
  end

  def ready_draft_shgs
    Shg
      .where(approval_status: "draft")
      .where(id: active_member_loan_shg_ids)
      .includes(:created_by, :village, :shg_members, :shg_loans)
      .with_attached_meeting_photo
      .with_attached_meeting_register
  end

  def active_member_loan_shg_ids
    ShgLoan.joins(:shg_member)
      .where(active: true, shg_members: { active: true })
      .select(:shg_id)
  end

  def ready_draft_shgs_csv(shgs)
    CSV.generate do |csv|
      csv << [
        "SHG ID", "SHG", "Village", "Created By", "Actor Role", "Meeting Photo",
        "Meeting Register", "Active Members", "Active Member Loans", "Next Status"
      ]
      shgs.find_each do |shg|
        csv << ready_draft_shg_row(shg)
      end
    end
  end

  def ready_draft_shg_row(shg)
    actor = shg.approval_submission_actor
    [
      shg.id,
      shg.name,
      shg.village&.name,
      shg.created_by&.name,
      actor&.user_type&.code,
      shg.meeting_photo.attached? ? "Yes" : "No",
      shg.meeting_register.attached? ? "Yes" : "No",
      shg.shg_members.where(active: true).count,
      shg.shg_loans.joins(:shg_member).where(active: true, shg_members: { active: true }).count,
      next_approval_status_for(actor)
    ]
  end

  def next_approval_status_for(actor)
    return "approved" if actor&.assistant_admin?
    return "pending_assistant" if actor&.district_coordinator?

    "pending_dc"
  end
end
