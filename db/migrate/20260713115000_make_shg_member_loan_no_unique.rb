class MakeShgMemberLoanNoUnique < ActiveRecord::Migration[8.1]
  class MigrationShgMember < ApplicationRecord
    self.table_name = "shg_members"
  end

  def change
    reversible do |dir|
      dir.up do
        sequence = MigrationShgMember
          .where("loan_no LIKE ?", "ASAWO24-%")
          .pluck(:loan_no)
          .filter_map { |value| value.to_s.split("-").last.to_i if value.to_s.match?(/\AASAWO24-\d+\z/) }
          .max
          .to_i

        MigrationShgMember.where(loan_no: [ nil, "" ]).order(:id).find_each do |member|
          sequence += 1
          member.update_columns(loan_no: "ASAWO24-#{sequence}")
        end
      end
    end

    remove_index :shg_members, :loan_no if index_exists?(:shg_members, :loan_no)
    add_index :shg_members, :loan_no, unique: true
  end
end
