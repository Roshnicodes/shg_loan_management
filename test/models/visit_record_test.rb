require "test_helper"

class VisitRecordTest < ActiveSupport::TestCase
  setup do
    @member = shg_members(:one)
    @shg = @member.shg
    @village = @shg.village
    @product = products(:one)
    @creator = users(:one)
  end

  test "assigns visit number per member" do
    first_visit = create_visit(Date.new(2026, 8, 1))
    second_visit = create_visit(Date.new(2026, 8, 2))

    assert_equal 1, first_visit.visit_number
    assert_equal 2, second_visit.visit_number
  end

  test "finds duplicate active visit for same member product and date" do
    existing_visit = create_visit(Date.new(2026, 8, 1))
    duplicate = VisitRecord.new(
      village: @village,
      shg: @shg,
      shg_member: @member,
      product: @product,
      visit_date: existing_visit.visit_date
    )

    assert_equal existing_visit, VisitRecord.duplicate_of(duplicate).first
  end

  private

  def create_visit(visit_date)
    VisitRecord.create!(
      village: @village,
      shg: @shg,
      shg_member: @member,
      product: @product,
      visit_date: visit_date,
      purpose: "Follow up",
      observations: "Checked",
      created_by: @creator
    )
  end
end
