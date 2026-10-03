require_relative "test_helper"

class PaginationTest < ActiveSupport::TestCase
  test "an empty collection has one readable page" do
    page = OpenBlog::Pagination.page(OpenBlog::Post.where(slug: "missing"), page: nil, per_page: 12)
    assert_equal [ [], 1, 1 ], [ page.records, page.page, page.total_pages ]
    assert_raises(OpenBlog::NotFound) { OpenBlog::Pagination.page(OpenBlog::Post.all, page: 2, per_page: 12) }
  end

  test "invalid page values are not silently coerced" do
    [ 0, -1, "", "0", "-2", "abc", "1.5", 1.2, [] ].each do |value|
      assert_raises(OpenBlog::NotFound) { OpenBlog::Pagination.page(OpenBlog::Post.all, page: value, per_page: 12) }
    end
  end
end
