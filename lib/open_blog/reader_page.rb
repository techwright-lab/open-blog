module OpenBlog
  class ReaderPage
    attr_reader :kind, :record, :pagination, :path, :breadcrumbs, :base_url

    def initialize(kind:, path:, base_url:, record: nil, pagination: nil, breadcrumbs: [])
      @kind, @record, @pagination, @path, @breadcrumbs, @base_url = kind, record, pagination, path, breadcrumbs, base_url.chomp("/")
    end

    def page_number
      pagination&.page || 1
    end

    def path_for(number)
      number > 1 ? "#{path}#{path.include?("?") ? "&" : "?"}page=#{number}" : path
    end

    def canonical_path
      path_for(page_number)
    end
  end
end
