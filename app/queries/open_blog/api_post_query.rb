module OpenBlog
  class ApiPostQuery
    FILTERS = %i[status category tag author series q page per_page].freeze

    def self.call(filters, base_url: nil)
      new(filters, base_url: base_url).call
    end

    def initialize(filters, base_url:)
      @filters, @base_url = filters, base_url
    end

    def call
      page = positive_integer(:page, 1)
      per_page = [ positive_integer(:per_page, 25), 100 ].min
      relation = Post.all
      if @filters.key?(:status)
        invalid(:status) unless Post.statuses.key?(@filters[:status])
        relation = relation.where(status: @filters[:status])
      end
      { category: :category, tag: :tags, author: :author, series: :series }.each do |field, association|
        next unless @filters.key?(field)
        value = @filters[field]
        invalid(field) unless value.is_a?(String) && value.present?
        model = Post.reflect_on_association(association).klass
        matches = model.where(slug: value).or(model.where(name: value))
        matches = matches.or(model.where(id: value.to_i)) if value.match?(/\A[1-9]\d*\z/)
        relation = relation.joins(association).merge(matches)
      end
      if @filters.key?(:q)
        query = @filters[:q]
        invalid(:q) unless query.is_a?(String)
        relation = relation.where("LOWER(open_blog_posts.search_text) LIKE ?", "%#{Post.sanitize_sql_like(query.downcase)}%") if query.present?
      end
      relation = relation.distinct
      total = relation.count
      posts = relation.order(created_at: :desc, id: :desc).offset((page - 1) * per_page).limit(per_page)
        .includes(:author, :category, :tags, :public_revision)
      { posts: posts.map { |post| PostSerializer.call(post, card: true, base_url: @base_url) }, page: page, per_page: per_page, total: total }
    end

    private

    def positive_integer(field, default)
      return default unless @filters.key?(field)
      value = @filters[field]
      invalid(field) unless (value.is_a?(Integer) || value.is_a?(String)) && value.to_s.match?(/\A[1-9]\d*\z/) && value.to_s.length <= 9
      value.to_i
    end

    def invalid(field)
      raise Error::ValidationFailed.new(details: [ field.to_s ])
    end
  end
end
