class MakeUserLoginAndEmailUniqueForActiveUsers < ActiveRecord::Migration[8.1]
  def up
    remove_index :users, name: "index_users_on_email"
    remove_index :users, name: "index_users_on_login_id"

    add_index :users, "LOWER(email)", unique: true, where: "active = true", name: "index_active_users_on_lower_email"
    add_index :users, "LOWER(login_id)", unique: true, where: "active = true", name: "index_active_users_on_lower_login_id"
  end

  def down
    remove_index :users, name: "index_active_users_on_lower_email"
    remove_index :users, name: "index_active_users_on_lower_login_id"

    add_index :users, :email, unique: true, name: "index_users_on_email"
    add_index :users, :login_id, unique: true, name: "index_users_on_login_id"
  end
end
