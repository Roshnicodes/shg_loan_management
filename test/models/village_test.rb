require "test_helper"

class VillageTest < ActiveSupport::TestCase
  test "moving village to another block syncs shg location references" do
    village = villages(:one)
    new_block = blocks(:two)

    village.update!(block: new_block)

    shg = shgs(:one).reload
    assert_equal new_block, shg.block
    assert_equal new_block.district, shg.district
    assert_equal new_block.district.state, shg.state
  end
end
