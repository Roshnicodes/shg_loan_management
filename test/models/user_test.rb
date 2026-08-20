require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "crp can remove mapped blocks and villages on edit" do
    crp_type = UserType.create!(name: "CRP - Village", code: "CRP", level: "village", active: true)
    state = State.create!(name: "Test State Remove", code: "TSR", active: true)
    district = District.create!(name: "Test District Remove", code: "TDR", state: state, active: true)
    block = Block.create!(name: "Test Block Remove", code: "TBR", district: district, active: true)
    village = Village.create!(name: "Test Village Remove", code: "TVR", block: block, active: true)

    user = User.create!(
      name: "Mapping Remove CRP",
      email: "mapping-remove@example.com",
      login_id: "mapping_remove_crp",
      mobile: "9876543210",
      designation: "CRP",
      user_type: crp_type,
      state: state,
      district: district,
      mapped_block_ids: [ block.id ],
      mapped_village_ids: [ village.id ],
      password: "secret123",
      password_confirmation: "secret123",
      active: true
    )

    assert_equal [ block.id ], user.office_block_ids
    assert_equal [ village.id ], user.office_village_ids

    user.update!(mapped_block_ids: [], mapped_village_ids: [])

    user.reload
    assert_nil user.block_id
    assert_nil user.village_id
    assert_empty user.mapped_block_ids
    assert_empty user.mapped_village_ids
    assert_empty user.office_block_ids
    assert_empty user.office_village_ids
  end
end
