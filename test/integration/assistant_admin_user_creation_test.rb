require "test_helper"

class AssistantAdminUserCreationTest < ActionDispatch::IntegrationTest
  test "assistant admin can add users" do
    state = State.create!(name: "Assistant User State", active: true)
    district = District.create!(name: "Assistant User District", state: state, active: true)
    block = Block.create!(name: "Assistant User Block", district: district, active: true)
    village = Village.create!(name: "Assistant User Village", block: block, active: true)
    assistant_type = UserType.create!(name: "Assistant Admin", code: "ASSIST_ADMIN", level: "state", active: true)
    crp_type = UserType.create!(name: "CRP", code: "CRP", level: "village", active: true)
    assistant = create_user("104", assistant_type, state)

    post login_path, params: { login_id: assistant.login_id, password: "secret123" }

    assert_difference("User.count", 1) do
      post users_path, params: {
        user: {
          name: "Created CRP",
          email: "created-crp@example.com",
          mobile: "9876502222",
          user_type_id: crp_type.id,
          state_id: state.id,
          mapped_district_ids: [ district.id ],
          mapped_block_ids: [ block.id ],
          mapped_village_ids: [ village.id ],
          password: "secret123",
          password_confirmation: "secret123",
          active: "1"
        }
      }
    end
    assert_redirected_to users_path
  end

  private

  def create_user(login_id, user_type, state)
    User.create!(
      name: login_id.titleize,
      email: "#{login_id}@example.com",
      login_id: login_id,
      mobile: "9876501111",
      user_type: user_type,
      state: state,
      password: "secret123",
      active: true
    )
  end
end
