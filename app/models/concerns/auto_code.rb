module AutoCode
  extend ActiveSupport::Concern

  included do
    before_validation :assign_auto_code, if: -> { respond_to?(:code) && code.blank? }
  end

  private

  def assign_auto_code
    base = name.to_s.parameterize(separator: "").upcase.first(10)
    base = self.class.name.upcase.first(3) if base.blank?
    candidate = base
    counter = 1

    while self.class.where(code: candidate).where.not(id: id).exists?
      counter += 1
      candidate = "#{base}#{counter}"
    end

    self.code = candidate
  end
end
