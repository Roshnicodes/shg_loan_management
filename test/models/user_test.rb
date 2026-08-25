require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "new users get a three digit login id when blank" do
    user_type = UserType.create!(name: "Auto Login Admin", code: "ADMIN", level: "state", active: true)
    state = State.create!(name: "Auto Login State", code: "ALS", active: true)

    user = User.create!(
      name: "Auto Login User",
      email: "auto-login@example.com",
      mobile: "9876543299",
      user_type: user_type,
      state: state,
      password: "secret123",
      password_confirmation: "secret123",
      active: true
    )

    assert_match(/\A\d{3}\z/, user.login_id)
  end

  test "existing non numeric usernames remain valid when unchanged" do
    user_type = UserType.create!(name: "Legacy Admin", code: "ADMIN", level: "state", active: true)
    state = State.create!(name: "Legacy State", code: "LS", active: true)
    user = User.new(
      name: "Legacy User",
      email: "legacy-user@example.com",
      login_id: "legacy_user",
      mobile: "9876543298",
      user_type: user_type,
      state: state,
      password: "secret123",
      password_confirmation: "secret123",
      active: true
    )
    user.save!(validate: false)

    assert user.update(name: "Legacy User Updated")
    assert_equal "legacy_user", user.reload.login_id
  end

  test "username must be unique even when existing user is inactive" do
    user_type = UserType.create!(name: "Unique Admin", code: "ADMIN", level: "state", active: true)
    state = State.create!(name: "Unique State", code: "US", active: true)
    User.create!(
      name: "Inactive Username User",
      email: "inactive-username@example.com",
      login_id: "111",
      mobile: "9876543297",
      user_type: user_type,
      state: state,
      password: "secret123",
      password_confirmation: "secret123",
      active: false
    )

    duplicate = User.new(
      name: "Duplicate Username User",
      email: "duplicate-username@example.com",
      login_id: "111",
      mobile: "9876543296",
      user_type: user_type,
      state: state,
      password: "secret123",
      password_confirmation: "secret123",
      active: true
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:login_id], "has already been taken"
  end

  test "crp can remove mapped blocks and villages on edit" do
    crp_type = UserType.create!(name: "CRP - Village", code: "CRP", level: "village", active: true)
    state = State.create!(name: "Test State Remove", code: "TSR", active: true)
    district = District.create!(name: "Test District Remove", code: "TDR", state: state, active: true)
    block = Block.create!(name: "Test Block Remove", code: "TBR", district: district, active: true)
    village = Village.create!(name: "Test Village Remove", code: "TVR", block: block, active: true)

    user = User.create!(
      name: "Mapping Remove CRP",
      email: "mapping-remove@example.com",
      login_id: "101",
      mobile: "9876543210",
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
