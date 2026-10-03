require "uri"
require "json"
require "nokogiri"

module OpenBlog
  class SurfaceReport
    autoload :Http, "open_blog/surface_report/http"
    autoload :Robots, "open_blog/surface_report/robots"
    autoload :PageChecks, "open_blog/surface_report/page_checks"
    autoload :ExpectedContent, "open_blog/surface_report/expected_content"
    autoload :RecordChecks, "open_blog/surface_report/record_checks"
    autoload :ReachChecks, "open_blog/surface_report/reach_checks"

    STATUSES = [ "pass", "fail", "not applicable", "not verified" ].freeze
    LIMIT = 50
    NOTICE = "Automated observations do not establish editorial quality or replace manual review, browser testing, and field measurements.".freeze
    NOT_ASSESSED = %w[E2 E9 E10 E11 E12 E13 E14 E15 E23 E24 E25].freeze
    NOT_RUN = [
      { predicate: "T12_render", reason: "Small-screen layout requires a browser session." },
      { predicate: "T18", reason: "Hidden content and navigation behavior need manual inspection." },
      { predicate: "T19", reason: "Accessibility requires browser tooling and human testing." },
      { predicate: "T20", reason: "Performance assessment needs real-user field measurements." }
    ].freeze

    def self.run(scope: :site, post: nil, page: 1, reach: false, http: nil)
      context = Context.new(scope: scope, post: post, page: page, reach: reach, http: http)
      PageChecks.new(context).call
      RecordChecks.new(context).call
      ReachChecks.new(context).call unless context.scope == :site
      Result.new(context)
    end

    def self.declarations
      {
        field_map: { title: "posts.title", description: "posts.description", search_title: "posts.search_title",
          search_description: "posts.search_description", body: "posts.body_markdown or rich_body", author: "posts.author_name",
          images: "cover_image, body image manifest, social_image", faq: "faqs.question and faqs.answer ordered by position" },
        content_selector: "[data-open-blog-content]", faq_selectors: OpenBlog::FAQ_SELECTORS.values,
        primary_list_type: OpenBlog.config.primary_list_type, sign_in_destinations: OpenBlog.config.sign_in_destinations
      }
    end

    class Page
      attr_reader :url, :status, :headers, :body, :error

      def initialize(url:, status: 0, headers: {}, body: "", error: nil)
        @url, @status, @body, @error = url, status.to_i, body, error
        @headers = headers.to_h.transform_keys { |key| key.to_s.downcase }
      end

      def document
        @document ||= Nokogiri::HTML5.parse(body.to_s.dup.force_encoding(Encoding::UTF_8).scrub)
      end

      def articles
        @articles ||= document.css('script[type="application/ld+json"]').flat_map do |script|
          json_nodes(JSON.parse(script.text))
        rescue JSON::ParserError
          []
        end.select { |node| (Array(node["@type"]) & %w[Article BlogPosting]).any? }
      end

      def article
        articles.first
      end

      private

      def json_nodes(value)
        case value
        when Array then value.flat_map { |item| json_nodes(item) }
        when Hash then [ value, *json_nodes(value["@graph"]) ]
        else []
        end
      end
    end

    class Context
      attr_reader :scope, :posts, :config, :now, :reach, :results, :pagination, :limitations

      def initialize(scope:, post:, page:, reach:, http:)
        @config, @now, @results, @pages = OpenBlog.config, Time.current, [], {}
        @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
        @response_bytes = 0
        @limitations = []
        @scope = scope.to_s.to_sym
        invalid!(:scope) unless %i[site post all].include?(@scope)
        page = page.to_i if page.is_a?(String) && page.match?(/\A[1-9]\d*\z/)
        invalid!(:page) unless page.is_a?(Integer) && page.between?(1, 1_000_000)
        @reach = case reach
        when true, "true" then true
        when false, "false" then false
        else invalid!(:reach)
        end
        invalid!(:post) if @scope == :post ? post.blank? : post.present?
        @http = http || Http.new(trusted_origin: config.public_base_url)
        select_posts(post, page)
      end

      def record(predicate, status, reason, post: nil, marks: [], details: nil)
        status = status.to_s.tr("_", " ")
        raise ArgumentError, "Unknown report status" unless STATUSES.include?(status)
        value = { predicate: predicate.to_s, result: status, reason: reason.to_s, marks: marks }
        value[:post_id] = post.respond_to?(:id) ? post.id : post if post
        value[:details] = details if details
        results << value
        value
      end

      def row(predicate, post: nil)
        id = post.respond_to?(:id) ? post.id : post
        results.find { |value| value[:predicate] == predicate.to_s && value[:post_id] == id }
      end

      def absolute(path)
        return if path.blank? || config.public_base_url.blank?
        URI.join("#{config.public_base_url.chomp('/')}/", path.to_s).to_s
      rescue URI::InvalidURIError, URI::BadURIError
        nil
      end

      def post_page(post)
        page(absolute(post.path))
      end

      def page(url)
        return Page.new(url: nil, error: "Set public_base_url to inspect reader pages.") if url.blank?
        return @pages[url] if @pages.key?(url)
        if @byte_budget_exhausted || @pages.length >= 500 || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline
          return limited_page(url, "Report request budget exhausted; narrow the scope and retry.")
        end
        @pages[url] ||= begin
          response = @http.get(url)
          @response_bytes += response.body.to_s.bytesize
          if @response_bytes > 32 * 1024 * 1024
            @byte_budget_exhausted = true
            limited_page(url, "Report response-byte budget exhausted; narrow the scope and retry.")
          else
            Page.new(url: url, status: response.status, headers: response.headers, body: response.body)
          end
        rescue Http::FetchError => error
          Page.new(url: url, error: error.message)
        end
      end

      def robots_allowed?(url, agent)
        return if url.blank?
        uri = URI.parse(url)
        target = URI.join(url, "/robots.txt").to_s
        6.times do |attempt|
          response = page(target)
          return if response.status.zero? || response.status >= 500
          return true if response.status.between?(400, 499)
          return Robots.allowed?(response.body, uri.request_uri, agent) if response.status == 200
          return unless [ 301, 302, 303, 307, 308 ].include?(response.status)
          return if response.headers["location"].blank? || attempt == 5
          target = URI.join(target, response.headers["location"]).to_s
        end
      rescue URI::InvalidURIError, URI::BadURIError
        nil
      end

      private

      def limited_page(url, reason)
        @limitations << reason unless @limitations.include?(reason)
        Page.new(url: url, error: reason)
      end

      def select_posts(identity, number)
        scope = Post.listed.order(:id)
        if @scope == :post
          identity = identity.id if identity.is_a?(Post)
          selected = scope.find_by(id: identity) if identity.to_s.match?(/\A\d+\z/)
          selected ||= scope.find_by(slug: identity.to_s)
          raise Error::NotFound unless selected
          @posts = [ selected ]
          @pagination = { page: 1, per_page: 1, total: 1, pages: 1 }
        else
          total = scope.count
          @posts = scope.offset((number - 1) * LIMIT).limit(LIMIT).to_a
          @pagination = { page: number, per_page: LIMIT, total: total, pages: (total.to_f / LIMIT).ceil }
        end
      end

      def invalid!(field)
        raise Error::ValidationFailed.new(details: [ field.to_s ])
      end
    end

    class Result
      def initialize(context)
        @data = { gem_version: OpenBlog::VERSION, report_version: "1", date: context.now.iso8601,
          scope: context.scope.to_s, post_ids: context.posts.map(&:id), pagination: context.pagination,
          declarations: SurfaceReport.declarations, results: context.results, limitations: context.limitations,
          counts: STATUSES.to_h { |status| [ status, context.results.count { |row| row[:result] == status } ] },
          not_run: NOT_RUN, not_assessed: NOT_ASSESSED, sentence: NOTICE }
      end

      def to_h
        @data.deep_dup
      end

      def to_text
        lines = [ "OpenBlog page and record report", "#{@data[:date]} | scope: #{@data[:scope]}",
          "Articles: #{@data[:post_ids].join(', ')} | page #{@data[:pagination][:page]} of #{@data[:pagination][:pages]}" ]
        lines << "Declarations: #{JSON.generate(@data[:declarations])}"
        @data[:results].each do |row|
          identity = row[:post_id] ? " article #{row[:post_id]}" : ""
          lines << "#{row[:predicate]}#{identity}: #{row[:result]} — #{row[:reason]}"
          lines << "  #{row[:marks].join('; ')}" if row[:marks].any?
          lines << "  Evidence: #{JSON.generate(row[:details])}" if row[:details]
        end
        lines << @data[:counts].map { |status, count| "#{status}: #{count}" }.join(" | ")
        lines << "Not run: #{@data[:not_run].map { |item| item[:predicate] }.join(', ')}"
        lines << "Not assessed: #{@data[:not_assessed].join(', ')}"
        @data[:limitations].each { |reason| lines << "Limit: #{reason}" }
        lines << NOTICE
        lines.join("\n") + "\n"
      end
    end
  end
end
