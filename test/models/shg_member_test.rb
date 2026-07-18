require "test_helper"

class ShgMemberTest < ActiveSupport::TestCase
  test "allows duplicate member names in same shg" do
    shg = shgs(:one)
    occupation = occupations(:one)

    first = ShgMember.create!(shg: shg, occupation: occupation, name: "Parwati Yadav", loan_no: "TEST-DUP-1")
    second = ShgMember.new(shg: shg, occupation: occupation, name: first.name, loan_no: "TEST-DUP-2")

    assert second.valid?
  end
end
