module OpenBlog
  class Pagination
    Page = Data.define(:records, :page, :total_pages)

    def self.page(scope, page:, per_page:)
      value = page.nil? ? 1 : page
      unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A[1-9]\d*\z/))
        raise NotFound
      end
      number = value.to_i
      raise NotFound unless number.positive? && per_page.is_a?(Integer) && per_page.positive?
      count = scope.reorder(nil).count
      total = [ (count.to_f / per_page).ceil, 1 ].max
      raise NotFound if number > total
      Page.new(records: scope.offset((number - 1) * per_page).limit(per_page).to_a, page: number, total_pages: total)
    end
  end
end
