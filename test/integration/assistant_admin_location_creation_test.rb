require "test_helper"

class AssistantAdminLocationCreationTest < ActionDispatch::IntegrationTest
  test "assistant admin can add allowed master records" do
    assistant = create_assistant_admin
    post login_path, params: { login_id: assistant.login_id, password: "secret123" }

    assert_difference("State.count", 1) do
      post states_path, params: { state: { name: "Assistant State", active: "1" } }
    end
    assert_redirected_to states_path
    state = State.find_by!(name: "Assistant State")

    assert_difference("District.count", 1) do
      post districts_path, params: { district: { state_id: state.id, name: "Assistant District", active: "1" } }
    end
    assert_redirected_to districts_path
    district = District.find_by!(name: "Assistant District")

    assert_difference("Block.count", 1) do
      post blocks_path, params: { block: { district_id: district.id, name: "Assistant Block", active: "1" } }
    end
    assert_redirected_to blocks_path
    block = Block.find_by!(name: "Assistant Block")

    assert_difference("Village.count", 1) do
      post villages_path, params: { village: { block_id: block.id, name: "Assistant Village", active: "1" } }
    end
    assert_redirected_to villages_path

    assert_difference("Product.count", 1) do
      post products_path, params: { product: { name: "Assistant Product", active: "1" } }
    end
    assert_redirected_to products_path

    assert_difference("LoanStatus.count", 1) do
      post loan_statuses_path, params: { loan_status: { name: "Assistant Loan Status", active: "1" } }
    end
    assert_redirected_to loan_statuses_path

    assert_difference("UserType.count", 1) do
      post user_types_path, params: { user_type: { name: "Assistant Role", level: "village", active: "1" } }
    end
    assert_redirected_to user_types_path
  end

  test "assistant admin can add multiple villages in one block" do
    assistant = create_assistant_admin
    post login_path, params: { login_id: assistant.login_id, password: "secret123" }
    state = State.create!(name: "Assistant Bulk State", active: true)
    district = District.create!(state: state, name: "Assistant Bulk District", active: true)
    block = Block.create!(district: district, name: "Assistant Bulk Block", active: true)

    assert_difference("Village.count", 2) do
      post villages_path, params: {
        village: {
          state_id: state.id,
          district_id: district.id,
          block_id: block.id,
          bulk_rows: [
            { name: "Assistant Bulk Village One", code: "ABV1" },
            { name: "Assistant Bulk Village Two", code: "ABV2" }
          ],
          active: "1"
        }
      }
    end

    assert_redirected_to villages_path
    assert_equal block, Village.find_by!(name: "Assistant Bulk Village One").block
    assert_equal "ABV2", Village.find_by!(name: "Assistant Bulk Village Two").code
  end

  private

  def create_assistant_admin
    assistant_type = UserType.create!(name: "Assistant Admin", code: "ASSIST_ADMIN", level: "state", active: true)
    state = State.create!(name: "Assistant Home State", active: true)

    User.create!(
      name: "Assistant Master Admin",
      email: "assistant-master@example.com",
      login_id: "105",
      mobile: "9812345678",
      user_type: assistant_type,
      state: state,
      password: "secret123",
      active: true
    )
  end
end
