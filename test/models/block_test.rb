require "test_helper"

class BlockTest < ActiveSupport::TestCase
  test "moving block to another district syncs shg location references" do
    block = blocks(:one)
    new_district = districts(:two)

    block.update!(district: new_district)

    shg = shgs(:one).reload
    assert_equal new_district, shg.district
    assert_equal new_district.state, shg.state
  end
end
