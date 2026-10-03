require "uri"
require "json"
require "time"

module OpenBlog
  class SurfaceReport
    class PageChecks
      PAGE_IDS = %w[E1 E3 E5 T3 T7 T8 T9 T10 T11 T12 T13 T15 T16 T17].freeze

      def initialize(context)
        @context = context
      end

      def call
        @context.posts.each { |post| check_post(post) } unless site_scope?
        check_policies
        check_sitemap
        check_feeds
        check_lists
      end

      private

      def site_scope?
        @context.respond_to?(:scope) && @context.scope == :site
      end

      def record(id, status, reason, **options)
        @context.record(id, status, reason, **options)
      end

      def outcome(id, valid, reason, **options)
        record(id, valid ? :pass : :fail, reason, **options)
      end

      def unavailable(page)
        page.status.to_i == 0 ? :not_verified : :fail
      end

      def check_post(post)
        page = @context.post_page(post)
        unless page.status == 200
          PAGE_IDS.each { |id| record(id, unavailable(page), "The post page could not be read successfully.", post: post) }
          return
        end
        doc, article = page.document, page.article || {}
        visible_author = doc.at_css(".ob-byline-author")
        author = article["author"]
        author = author.first if author.is_a?(Array)
        author = {} unless author.is_a?(Hash)
        outcome("E1", text(visible_author).present? && author["name"].present?, "Visible and structured author names are required.", post: post)
        author_url = resolve(page.url, visible_author&.[]("href")) if text(visible_author).present?
        author_page = @context.page(author_url)
        record("E3", author_url ? (author_page.status == 200 ? :pass : unavailable(author_page)) : :fail,
          "The visible author link must open successfully.", post: post)
        check_publication_date(post, doc)
        canonicals = doc.css("head link[rel~='canonical']")
        canonical = canonicals.first&.[]("href")
        expected = post.canonical_url.presence || @context.absolute(post.path)
        if canonicals.length != 1 || !absolute_http?(canonical) || canonical != expected
          record("T3", :fail, "One absolute canonical link must identify this post or its original.", post: post)
        else
          target = @context.page(canonical)
          record("T3", target.status == 200 ? :pass : unavailable(target), "The canonical destination must open successfully.", post: post)
        end
        { "T7" => "head title", "T8" => "head meta[name='description']" }.each do |id, selector|
          value = metadata(doc, selector)
          duplicates = @context.posts.count { |other| metadata(@context.post_page(other).document, selector) == value }
          outcome(id, value.present? && duplicates == 1, "The page needs a nonempty, distinct #{id == 'T7' ? 'title' : 'description'}.", post: post)
        end
        levels = doc.css("h1,h2,h3,h4,h5,h6").map { |node| node.name[1].to_i }
        outcome("T9", levels.each_cons(2).none? { |a, b| b > a + 1 }, "Heading levels must progress without skipping a level.", post: post)
        h1 = doc.css("h1")
        outcome("T10", h1.length == 1 && text(h1.first) == post.title.squish, "One main heading must contain the post title.", post: post)
        lang = doc.at_css("html")&.[]("lang").to_s
        outcome("T11", language_tag?(lang), "The document needs a language tag.", post: post)
        viewport = doc.at_css("head meta[name='viewport']")&.[]("content").to_s
        outcome("T12", viewport.match?(/(?:\A|[,;\s])width\s*=\s*device-width(?:\z|[,;\s])/i), "The viewport declaration must use device width.", post: post)
        outcome("T13", doc.css("img").all? { |image| image.key?("alt") }, "Every image needs an alt attribute, including decorative images.", post: post)
        structured = page.articles.length == 1 && article["headline"].present? && author["name"].present? && author["@type"].present? &&
          timestamp(article["datePublished"]) && timestamp(article["dateModified"]) && (!(post.cover_image || post.social_image) || article["image"].present?)
        outcome("T15", structured, post.published_at ? "Article data needs its title, author and publication dates, plus an image when used." : "The publication date is unknown in the imported history.", post: post)
        published, modified = timestamp(article["datePublished"]), timestamp(article["dateModified"])
        visible_published, visible_modified = visible_date(doc, :published), visible_date(doc, :updated)
        agrees = author["name"].to_s.squish == text(visible_author) && text(visible_author).present? && article["headline"].to_s.squish == post.title.squish &&
          published && modified && published <= @context.now && modified <= @context.now && visible_published == published.to_date &&
          (!doc.at_css(".ob-date--updated time") || visible_modified == modified.to_date)
        outcome("T16", agrees, "Structured author and dates must agree with visible content and cannot be in the future.", post: post)
        outcome("T17", %w[title type image url].all? { |field| doc.at_css("head meta[property='og:#{field}']")&.[]("content").present? },
          "Sharing metadata needs a title, type, image and URL.", post: post)
      end

      def check_publication_date(post, doc)
        first = post.publications.find_by(entry_type: "first")&.occurred_at
        baseline = post.baseline
        date = first || baseline&.first_published_at || baseline&.declared_first_published_at
        unless date
          return record("E5", :not_verified, "A reliable first publication date is unavailable.", post: post)
        end
        marks = !first && baseline&.first_published_at.nil? && baseline&.declared_first_published_at ? [ "publisher declaration" ] : []
        outcome("E5", visible_date(doc, :published) == date.to_date, "The labeled publication date must match the recorded first publication.", post: post, marks: marks)
      end

      def check_policies
        { "E4" => :responsible_party, "E8" => :corrections, "E16" => :editorial, "E17" => :ai_use }.each do |id, kind|
          url = @context.absolute(OpenBlog.policy_url(kind, config: @context.config))
          page = @context.page(url)
          status = url ? (page.status == 200 ? :pass : unavailable(page)) : (@context.config.public_base_url.present? ? :fail : :not_verified)
          if id == "E4" && @context.posts.any? && !site_scope?
            @context.posts.each do |post|
              post_page = @context.post_page(post)
              result = post_page.status == 200 ? status : unavailable(post_page)
              if result == :pass
                linked = post_page.document.css("a[href]").any? { |node| resolve(post_page.url, node["href"]) == url }
                result = :fail unless linked
              end
              record(id, result, "The responsible-party page must open and be linked from the post.", post: post)
            end
          else
            if id == "E4" && status == :pass
              statuses = @context.posts.map do |post|
                source = @context.post_page(post)
                next unavailable(source) unless source.status == 200
                source.document.css("a[href]").any? { |node| resolve(source.url, node["href"]) == url } ? :pass : :fail
              end
              status = combine(statuses)
            end
            record(id, status, "The configured policy page must open successfully.")
          end
        end
      end

      def check_sitemap
        page = @context.page(@context.absolute("#{OpenBlog.mount_path.chomp('/')}/sitemap.xml"))
        return record("T5", unavailable(page), "The sitemap could not be read successfully.") unless page.status == 200
        xml = Nokogiri::XML(page.body) { |options| options.strict.nonet }
        entries = xml.xpath("//*[local-name()='url']").to_h do |entry|
          [ entry.at_xpath("./*[local-name()='loc']")&.text, entry.at_xpath("./*[local-name()='lastmod']")&.text ]
        end
        valid = xml.root&.name == "urlset" && @context.posts.all? do |post|
          url = @context.absolute(post.path)
          canonical = post.canonical_url.presence || url
          if origin(canonical) != origin(url)
            !entries.key?(url)
          else
            value = entries[url]
            modified = modified_at(post)
            entries.key?(url) && (value.blank? || (calendar_date(value) == modified&.to_date && modified.present?))
          end
        end
        outcome("T5", valid, "Sitemap membership and modification dates must match public posts.")
      rescue Nokogiri::XML::SyntaxError
        record("T5", :fail, "The sitemap is not valid XML.")
      end

      def check_feeds
        pages = [ @context.page(@context.absolute(OpenBlog.mount_path)) ] + @context.posts.map { |post| @context.post_page(post) }
        statuses = pages.map do |page|
          next unavailable(page) unless page.status == 200
          links = page.document.css("head link[rel~='alternate']").select { |link| %w[application/atom+xml application/feed+json].include?(link["type"]) }
          next :fail if links.empty?
          checks = links.map do |link|
            feed = @context.page(resolve(page.url, link["href"]))
            next unavailable(feed) unless feed.status == 200
            valid_feed?(feed, link["type"]) ? :pass : :fail
          end
          combine(checks)
        end
        record("T6", combine(statuses), "Feed discovery, required fields and the newest post must be available.")
      end

      def valid_feed?(page, type)
        newest = ReaderQueries.posts.first
        url = newest && @context.absolute(newest.path)
        if type == "application/feed+json"
          feed = JSON.parse(page.body)
          return false unless feed.is_a?(Hash)
          items = feed["items"]
          feed["version"] == "https://jsonfeed.org/version/1.1" && feed["title"].is_a?(String) && items.is_a?(Array) &&
            items.all? { |item| item.is_a?(Hash) && item["id"].is_a?(String) && (item["content_html"].is_a?(String) || item["content_text"].is_a?(String)) } &&
            (!url || items.any? { |item| item["id"] == url })
        else
          xml = Nokogiri::XML(page.body) { |options| options.strict.nonet }
          ns = { "a" => "http://www.w3.org/2005/Atom" }
          xml.root&.name == "feed" && xml.root&.namespace&.href == ns["a"] && %w[id title updated].all? { |field| xml.at_xpath("/a:feed/a:#{field}", ns)&.text.present? } &&
            xml.xpath("/a:feed/a:entry", ns).all? { |entry| %w[id title updated].all? { |field| entry.at_xpath("a:#{field}", ns)&.text.present? } &&
              (entry.at_xpath("a:author/a:name", ns)&.text.present? || xml.at_xpath("/a:feed/a:author/a:name", ns)&.text.present?) } &&
            (!url || xml.xpath("/a:feed/a:entry/a:id", ns).any? { |entry| entry.text == url })
        end
      rescue JSON::ParserError, Nokogiri::XML::SyntaxError
        false
      end

      def check_lists
        return record("T21", :not_verified, "A primary list type is not configured.") unless @context.config.primary_list_type
        pages = list_urls.map { |url, primary| [ @context.page(url), primary ] }
        policies = OpenBlog::Page.published.reject { |page| @context.config.policy_urls[page.kind.to_sym].present? }
        visible = @context.posts.map { |post| @context.post_page(post) } + pages.map(&:first) +
          policies.map { |page| @context.page(@context.absolute(page.path)) }
        indexed = visible.select { |page| page.status == 200 && !robots(page).include?("noindex") }
        statuses = pages.map do |page, primary|
          next unavailable(page) unless page.status == 200
          directives = robots(page)
          next :fail if primary && directives.include?("noindex")
          next(directives.include?("nofollow") ? :fail : :pass) if directives.include?("noindex")
          unique = [ "head title", "head meta[name='description']" ].all? do |selector|
            value = metadata(page.document, selector)
            value.present? && indexed.count { |other| metadata(other.document, selector) == value } == 1
          end
          next :fail unless unique
          allowed = %w[Googlebot bingbot].map { |agent| @context.robots_allowed?(page.url, agent) }
          allowed.include?(false) ? :fail : (allowed.include?(nil) ? :not_verified : :pass)
        end
        record("T21", combine(statuses), "List visibility, crawler access and distinct metadata must agree with the configured list type.")
      end

      def list_urls
        mount = OpenBlog.mount_path.chomp("/")
        featured = ReaderQueries.featured
        paths = pagination_urls(mount.presence || "/", Post.listed.count - (featured ? 1 : 0), true)
        { category: Category, tag: Tag, author: Author, series: Series }.each do |kind, model|
          model.find_each do |record|
            path = "#{mount}/#{@context.config.route_segments.fetch(kind)}/#{record.slug}"
            paths.concat(pagination_urls(path, record.posts.listed.count, @context.config.primary_list_type.to_s.singularize == kind.to_s))
          end
        end
        paths
      end

      def pagination_urls(path, count, primary)
        total = [ (count.to_f / @context.config.posts_per_page).ceil, 1 ].max
        (1..total).map { |number| [ @context.absolute(number == 1 ? path : "#{path}?page=#{number}"), primary ] }
      end

      def robots(page)
        (page.document.css("meta[name='robots']").map { |node| node["content"] }.join(",") + "," + page.headers.to_h.find { |key, _| key.to_s.downcase == "x-robots-tag" }&.last.to_s).downcase.split(/[\s,]+/)
      end

      def modified_at(post)
        post.publications.where(entry_type: %w[substantive correction]).maximum(:occurred_at) || post.baseline&.last_modified_at ||
          post.publications.find_by(entry_type: "first")&.occurred_at || post.baseline&.first_published_at || post.baseline&.declared_first_published_at
      end

      def combine(statuses)
        statuses.include?(:fail) ? :fail : (statuses.include?(:not_verified) ? :not_verified : :pass)
      end

      def metadata(doc, selector)
        node = doc.at_css(selector)
        node&.name == "meta" ? node["content"].to_s.squish : text(node)
      end

      def text(node)
        return "" unless node && ![ node, *node.ancestors ].any? { |parent| parent.key?("hidden") || parent["aria-hidden"] == "true" }
        node.text.squish
      end

      def visible_date(doc, kind)
        wrapper = doc.at_css(".ob-date--#{kind}")
        return unless wrapper && text(wrapper.at_css("span")).present? && text(wrapper.at_css("time")).present?
        timestamp(wrapper.at_css("time")&.[]("datetime"))&.to_date
      end

      def language_tag?(value)
        value.match?(/\A(?:(?:[a-z]{2,3}(?:-[a-z]{3}){0,3}|[a-z]{4}|[a-z]{5,8})(?:-[a-z]{4})?(?:-(?:[a-z]{2}|[0-9]{3}))?(?:-(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3}))*(?:-[0-9a-wy-z](?:-[a-z0-9]{2,8})+)*(?:-x(?:-[a-z0-9]{1,8})+)?|x(?:-[a-z0-9]{1,8})+)\z/i)
      end

      def calendar_date(value)
        timestamp(value)&.to_date || Date.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def timestamp(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def absolute_http?(value)
        uri = URI.parse(value.to_s)
        uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      rescue URI::InvalidURIError
        false
      end

      def resolve(base, path)
        return unless base.present? && path.present?
        url = URI.join(base, path).to_s
        url if absolute_http?(url)
      rescue URI::InvalidURIError
        nil
      end

      def origin(url)
        uri = URI.parse(url.to_s)
        [ uri.scheme, uri.host&.downcase, uri.port ]
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
