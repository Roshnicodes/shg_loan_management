require "test_helper"

class DistrictTest < ActiveSupport::TestCase
  test "moving district to another state syncs shg state references" do
    district = districts(:one)
    new_state = states(:two)

    district.update!(state: new_state)

    assert_equal new_state, shgs(:one).reload.state
  end
end
