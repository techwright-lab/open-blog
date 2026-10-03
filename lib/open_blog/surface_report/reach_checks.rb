require "uri"

module OpenBlog
  class SurfaceReport
    class ReachChecks
      REDIRECTS = [ 301, 302, 303, 307, 308 ].freeze
      SIGN_IN_PATH = %r{(?:\A|/)(?:login|log-in|signin|sign-in|sign_in|sign-on)(?:/|\z)}i

      def initialize(context)
        @context = context
      end

      def call
        unless @context.reach
          %w[T1 T2 T14].each { |key| @context.record(key, "not_verified", "Network checks were not requested.") }
          return
        end
        @context.posts.each do |post|
          page = @context.post_page(post)
          if page.status == 0
            %w[T1 T2 T14].each { |key| record(key, "not_verified", "The public page could not be fetched.", post) }
            next
          end
          crawler_check(post, page)
          transport_check(post, page)
          link_check(post, page)
        end
      end

      private

      def crawler_check(post, page)
        if page.status != 200 || page.document.at_css("[data-open-blog-content]").nil? || page.document.at_css("[data-open-blog-content]").text.strip.empty? || noindex?(page)
          return record("T1", "fail", "The page is unavailable, empty, or excludes search indexing.", post)
        end
        allowed = %w[Googlebot bingbot].map { |agent| @context.robots_allowed?(page.url, agent) }
        if allowed.include?(false)
          record("T1", "fail", "A search crawler is blocked by robots rules.", post)
        elsif allowed.include?(nil)
          record("T1", "not_verified", "Crawler access rules could not be checked.", post)
        else
          record("T1", "pass", "The page permits both checked search crawlers.", post)
        end
      end

      def noindex?(page)
        values = page.document.css("meta[name]").filter_map do |node|
          node["content"] if %w[robots googlebot bingbot].include?(node["name"].to_s.downcase)
        end
        header = page.headers["x-robots-tag"].to_s
        agent = nil
        header.split(",").each do |part|
          if part.include?(":")
            prefix, directive = part.split(":", 2)
            if prefix.strip.match?(/\A[a-z_-]+\z/i)
              agent = prefix.strip.downcase
              part = directive
            end
          end
          values << part if agent.nil? || %w[googlebot bingbot].include?(agent)
        end
        values.any? { |value| value.to_s.match?(/\b(?:noindex|none)\b/i) }
      end

      def transport_check(post, page)
        secure = URI(page.url)
        secure.scheme = "https"
        secure.port = nil if secure.port == 80
        secured = secure.to_s == page.url ? page : @context.page(secure.to_s)
        plain = secure.dup
        plain.scheme = "http"
        plain.port = nil if plain.port == 443
        response = @context.page(plain.to_s)
        if secured.status == 0 || response.status == 0
          return record("T2", "not_verified", "Both transport variants could not be fetched.", post)
        end
        destination = resolve(response.url, response.headers["location"])
        passed = secured.status == 200 && REDIRECTS.include?(response.status) && destination && URI(destination).scheme == "https"
        record("T2", passed ? "pass" : "fail", passed ? "HTTPS is available and HTTP redirects to HTTPS." : "HTTPS or the HTTP upgrade is missing.", post)
      rescue URI::InvalidURIError
        record("T2", "fail", "The transport redirect has an invalid destination.", post)
      end

      def link_check(post, page)
        unless page.status == 200
          return record("T14", "not_verified", "Links require an available page.", post)
        end
        links = page.document.css("a[href]").filter_map { |node| resolve(page.url, node["href"]) }.uniq
        links.select! { |url| origin(url) == origin(page.url) }
        statuses = links.map { |url| check_link(url) }
        failed = statuses.select { |entry| entry[:result] == "fail" }
        unknown = statuses.select { |entry| entry[:result] == "not_verified" }
        status = failed.any? ? "fail" : unknown.any? ? "not_verified" : "pass"
        reasons = { "pass" => "Same-site links meet the response checks.", "fail" => "Some same-site links failed the response checks.", "not_verified" => "Some link destinations could not be classified or fetched." }
        record("T14", status, reasons.fetch(status), post, details: statuses.reject { |entry| entry[:result] == "pass" })
      end

      def check_link(url)
        response = @context.page(url)
        return { url: url, result: "not_verified" } if response.status == 0
        declaration = @context.config.sign_in_destinations
        declared = Array(declaration).any? { |prefix| URI(url).path.start_with?(prefix) }
        redirected = REDIRECTS.include?(response.status)
        if redirected
          destination = resolve(response.url, response.headers["location"])
          return { url: url, result: "fail" } unless destination
          response = @context.page(destination)
        end
        return { url: url, result: "not_verified" } if response.status == 0
        sign_in = URI(response.url).path.match?(SIGN_IN_PATH) || response.document.at_css('input[type="password"]') || [ 401, 403 ].include?(response.status)
        result = if !declared && sign_in && declaration.nil?
          "not_verified"
        elsif declared
          ([ 200, 401, 403 ].include?(response.status) || (redirected && sign_in)) && !REDIRECTS.include?(response.status) ? "pass" : "fail"
        else
          response.status == 200 && !sign_in ? "pass" : "fail"
        end
        { url: url, result: result }
      end

      def resolve(base, reference)
        return unless reference.is_a?(String) && reference.present?
        uri = URI.join(base, reference)
        return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError, URI::BadURIError
        nil
      end

      def origin(url)
        uri = URI(url)
        [ uri.scheme, uri.host&.downcase, uri.port ]
      end

      def record(key, status, reason, post, details: nil)
        @context.record(key, status, reason, post: post, details: details)
      end
    end
  end
end
