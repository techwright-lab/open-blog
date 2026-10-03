module OpenBlog
  module PageViews
    BOT_PATTERN = /bot|crawler|spider|slurp|preview|monitor|curl|wget|headless|facebookexternalhit|WhatsApp|ChatGPT-User|Claude-User|Perplexity-User|anthropic-ai|cohere-ai|Google-InspectionTool/i

    module_function

    def count!(post, request, now: Time.current)
      return unless OpenBlog.config.page_views && post.published? && request.get? && request.format.html?
      return if request.user_agent.blank? || OpenBlog.config.page_view_bot_pattern.match?(request.user_agent)
      return if request.headers["Sec-Purpose"].to_s.match?(/prefetch/i)

      connection = PageView.connection
      table = connection.quote_table_name(PageView.table_name)
      connection.execute("INSERT INTO #{table} (post_id, day, views) VALUES (#{connection.quote(post.id)}, #{connection.quote(now.utc.to_date)}, 1) ON CONFLICT (post_id, day) DO UPDATE SET views = #{table}.views + 1")
      nil
    rescue StandardError => error
      Rails.logger.warn("OpenBlog page view counter failed: #{error.class.name}")
      nil
    end

    def for(post, from: nil, to: nil, now: Time.current)
      to = date(to, :to) || now.utc.to_date
      from = date(from, :from) || to - 29
      invalid!(:from) if from > to
      days = PageView.where(post_id: post.id, day: from..to).order(:day).pluck(:day, :views).map { |day, views| { day: day, views: views } }
      { post_id: post.id, from: from, to: to, total: days.sum { |row| row[:views] }, days: days }
    end

    def top(days: 30, limit: 5, base_url: nil, scope: Post.all, now: Time.current)
      days = positive(days, :days, 36500)
      limit = positive(limit, :limit, 100)
      today = now.utc.to_date
      totals = PageView.where(day: (today - days + 1)..today, post_id: scope.select(:id))
        .group(:post_id).order(Arel.sql("SUM(views) DESC"), :post_id).limit(limit).pluck(:post_id, Arel.sql("SUM(views)"))
      posts = Post.where(id: totals.map(&:first)).index_by(&:id)
      { days: days, posts: totals.filter_map do |id, views|
        post = posts[id]
        next unless post
        { id: id, slug: post.slug, title: post.title, url: post.url(base: OpenBlog.config.public_base_url || base_url), views: views }
      end }
    end

    def prune!(now: Time.current)
      retention = OpenBlog.config.page_view_retention_days
      return 0 if retention.nil?
      invalid!(:page_view_retention_days) unless retention.is_a?(Integer) && retention.positive?
      PageView.where("day < ?", now.utc.to_date - retention).delete_all
    end

    def date(value, field)
      return value if value.is_a?(Date)
      return nil if value.nil?
      invalid!(field) unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(value)
    rescue Date::Error
      invalid!(field)
    end
    private_class_method :date

    def positive(value, field, maximum)
      value = value.to_i if value.is_a?(String) && value.match?(/\A[1-9]\d*\z/)
      invalid!(field) unless value.is_a?(Integer) && value.between?(1, maximum)
      value
    end
    private_class_method :positive

    def invalid!(field)
      raise Error::ValidationFailed.new(details: [ field.to_s ])
    end
    private_class_method :invalid!
  end
end
