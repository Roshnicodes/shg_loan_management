require "test_helper"

class ShgTest < ActiveSupport::TestCase
  test "does not allow duplicate shg names case insensitive" do
    existing = shgs(:one)
    duplicate = Shg.new(
      state: states(:two),
      district: districts(:two),
      block: blocks(:two),
      village: villages(:two),
      name: existing.name.downcase,
      shg_code: "UNIQUE-SHG-CODE"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "display name includes shg id and village" do
    shg = shgs(:one)

    assert_equal "#{shg.name} / #{shg.id} / #{shg.village.name}", shg.display_name
  end
end
