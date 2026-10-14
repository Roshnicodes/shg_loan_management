require "test_helper"

class ApprovalNotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @state = State.create!(name: "Mail State", code: "MLS")
    @district = District.create!(name: "Mail District", code: "MLD", state: @state)
    @other_district = District.create!(name: "Other Mail District", code: "OMD", state: @state)
    @block = Block.create!(name: "Mail Block", code: "MLB", district: @district)
    @village = Village.create!(name: "Mail Village", code: "MLV", block: @block)

    @crp = user_for("261", UserType.create!(name: "Mail CRP", code: "CRP", level: "village"), district: @district)
    dc_type = UserType.create!(name: "Mail DC", code: "DIST_COORDINATOR", level: "district")
    @dc = user_for("262", dc_type, district: @district)
    @other_dc = user_for("263", dc_type, district: @other_district)
    @assistant = user_for("264", UserType.create!(name: "Mail AA", code: "ASSIST_ADMIN", level: "state"), district: nil)

    @shg = Shg.new(
      name: "Mail SHG",
      shg_code: "ML-SHG",
      state: @state,
      district: @district,
      block: @block,
      village: @village,
      office_location: "Mail Office",
      borrower_short_address: "Mail Village",
      linkage_date: Date.current,
      created_by: @crp
    )
    attach_required_shg_files(@shg)
    @shg.save!
  end

  test "submitted records go to the district coordinators of that district" do
    mails = ApprovalNotifier.mails_for(@shg, event: :submitted, actor: @crp)

    assert_equal [ @dc.email ], mails.map { |mail, _| mail["to_email"] }
    assert_equal "approval_pending", mails.first.last
    assert_includes mails.first.first["message"], "Mail SHG"
  end

  test "dc approval goes to assistant admins and completion goes to the creator and dc" do
    assert_equal [ @assistant.email ], ApprovalNotifier.mails_for(@shg, event: :pending_assistant, actor: @dc).map { |mail, _| mail["to_email"] }

    @shg.dc_approved_by = @dc
    approved = ApprovalNotifier.mails_for(@shg, event: :approved, actor: @assistant)
    assert_equal [ @crp.email, @dc.email ].sort, approved.map { |mail, _| mail["to_email"] }.sort
    assert approved.all? { |_, kind| kind == "approval_approved" }
  end

  test "returned records go to the creator and the dc but never to the actor" do
    mails = ApprovalNotifier.mails_for(@shg, event: :returned, actor: @dc, remark: "Fix photo")

    assert_equal [ @crp.email ], mails.map { |mail, _| mail["to_email"] }
    assert_includes mails.first.first["message"], "Fix photo"
  end

  test "approval actions queue mails only when the relay is configured" do
    @shg.update_columns(approval_status: "pending_dc")

    with_relay_url(nil) do
      assert_no_enqueued_jobs(only: NotificationMailJob) { @shg.reload.reject!(@dc, "Wrong group") }
    end

    @shg.update_columns(approval_status: "pending_dc")
    with_relay_url("https://krai.example.test/") do
      assert_enqueued_jobs(1, only: NotificationMailJob) { @shg.reload.return_for_correction!(@dc, "Fix photo") }
      assert_enqueued_jobs(0, only: NotificationMailJob) { ApprovalNotifier.silence { @shg.reload.reject!(@dc, "Wrong group") } }
    end
  end

  test "relay builds the krai address with the mail fields" do
    with_relay_url("https://krai.example.test/") do
      uri = NotificationMailRelay.request_uri({ "to_email" => "dc@example.com", "to_name" => "DC", "subject" => "S", "message" => "M", "link" => "" }, "approval_pending")

      assert_equal "https://krai.example.test/wash360_nnotify.aspx", "#{uri.scheme}://#{uri.host}#{uri.path}"
      assert_equal "dc@example.com", URI.decode_www_form(uri.query).to_h["to_email"]
    end
  end

  private

  def with_relay_url(value)
    previous = ENV["NOTIFICATION_MAIL_RELAY_URL"]
    value.nil? ? ENV.delete("NOTIFICATION_MAIL_RELAY_URL") : ENV["NOTIFICATION_MAIL_RELAY_URL"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("NOTIFICATION_MAIL_RELAY_URL") : ENV["NOTIFICATION_MAIL_RELAY_URL"] = previous
  end

  def user_for(login_id, user_type, district:)
    User.create!(
      name: "Mail User #{login_id}",
      email: "mail-#{login_id}@example.com",
      login_id: login_id,
      mobile: "9876543#{login_id}",
      user_type: user_type,
      state: @state,
      district: district,
      password: "secret123",
      active: true
    )
  end
end
