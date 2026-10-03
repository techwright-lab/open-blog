require "digest"
require "time"
require_relative "expected_content"

module OpenBlog
  class SurfaceReport
    class RecordChecks
      GENERATED = ".ob-notice, .ob-highlights, .ob-date, .ob-toc, .ob-correction, .ob-disclosure, [data-open-blog-preview]".freeze

      def initialize(context)
        @context = context
      end

      def call
        posts = @context.respond_to?(:scope) && @context.scope == :site ? [] : @context.posts
        posts.each do |post|
          modified_date(post)
          corrections(post)
          approval(post)
          revision(post)
          notice(post)
          connections(post)
        end
        redirects
      end

      private

      def record(predicate, status, reason, post: nil, **options)
        @context.record(predicate, status, reason, post: post, **options)
      end

      def readable(page)
        page && page.status == 200 && page.body
      end

      def modified_date(post)
        latest = post.publications.where(entry_type: %w[substantive correction]).where("occurred_at <= ?", @context.now).maximum(:occurred_at)
        baseline = post.baseline
        expected = latest || baseline&.last_modified_at || (!baseline && post.publications.find_by(entry_type: "first")&.occurred_at)
        return record("E6", :not_verified, "The release history has no supported modification date.", post: post) unless expected
        page = @context.post_page(post)
        sitemap = @context.page(@context.absolute("#{OpenBlog.mount_path.chomp('/')}/sitemap.xml"))
        return record("E6", :not_verified, "The article or sitemap could not be inspected.", post: post) unless readable(page) && readable(sitemap)
        xml = Nokogiri::XML(sitemap.body) { |options| options.strict.nonet }
        entry = xml.xpath("//*[local-name()='url']").find { |node| node.at_xpath("./*[local-name()='loc']")&.text == @context.absolute(post.path) }
        values = [ page.article&.fetch("dateModified", nil) ]
        sitemap_date = entry&.at_xpath("./*[local-name()='lastmod']")&.text
        values << sitemap_date if sitemap_date.present?
        values.concat(page.document.css(".ob-date--updated time").map { |node| node["datetime"] })
        valid = values.all? { |value| same_time?(value, expected) }
        record("E6", valid ? :pass : :fail, valid ? "Displayed modification dates agree with release history." : "A modification date differs from release history.", post: post)
      rescue Nokogiri::XML::SyntaxError
        record("E6", :fail, "The sitemap date evidence is not valid XML.", post: post)
      end

      def corrections(post)
        entries = post.publications.where(entry_type: "correction").where("occurred_at <= ?", @context.now).to_a
        return record("E7", :not_applicable, "No correction release is recorded.", post: post) if entries.empty?
        page = @context.post_page(post)
        return record("E7", :not_verified, "The article could not be inspected.", post: post) unless readable(page)
        blocks = page.document.css(".ob-correction")
        label = I18n.t("open_blog.notices.correction", locale: @context.config.locale)
        valid = entries.all? { |entry| blocks.any? { |block| visible_text(block).include?(label) && block.css("time").any? { |node| same_time?(node["datetime"], entry.occurred_at) } } }
        record("E7", valid ? :pass : :fail, valid ? "Recorded corrections have dated notices." : "A recorded correction lacks a dated notice.", post: post)
      end

      def approved(post)
        post.approvals.where(revision_id: post.public_revision_id, facts_checked: true).order(:approved_at, :id).first
      end

      def approval(post)
        return record("E18", :not_applicable, "The article is recorded as written by a person.", post: post) if post.provenance_human_written?
        review = approved(post)
        unless review
          return record("E18", post.provenance_unknown? ? :not_verified : :fail, "No fact-checked review covers the public revision.", post: post)
        end
        baseline = post.baseline
        released = if baseline && baseline.adopted_revision_id == post.public_revision_id
          baseline.first_published_at || baseline.declared_first_published_at
        else
          post.publications.where(revision_id: post.public_revision_id).minimum(:occurred_at)
        end
        marks = []
        marks << "publisher declaration" if review.kind == "declared"
        marks << "review after release" if released && review.approved_at > released
        record("E18", :pass, "A fact-checked review covers the public revision.", post: post, marks: marks,
          details: { approved_at: review.approved_at.iso8601, released_at: released&.iso8601 })
      end

      def revision(post)
        return record("E19", :not_applicable, "The article is recorded as written by a person.", post: post) if post.provenance_human_written?
        stored = post.public_revision
        page = @context.post_page(post)
        unless stored && readable(page) && (!post.provenance_unknown? || approved(post))
          return record("E19", :not_verified, "The revision, review, or fetched article is unavailable.", post: post)
        end
        payload = JSON.parse(stored.payload)
        expected = ExpectedContent.call(post, payload, base_url: @context.config.public_base_url)
        actual = page.document.at_css("[data-open-blog-content]")
        return record("E19", :not_verified, "The stored revision content could not be rendered.", post: post) unless expected
        return record("E19", :fail, "The fetched page has no declared article content region.", post: post) unless actual
        parts = {}
        linked = post.publications.exists?(revision_id: stored.id) && approved(post)
        parts["A"] = mark(Digest::SHA256.hexdigest(stored.payload) == stored.identifier && linked && RevisionPayload.new(post).identifier == stored.identifier)
        parts["B"] = mark(text(project(expected)) == text(project(actual)))
        parts["C"] = mark(links(project(expected)) == links(project(actual)))
        images = payload.fetch("images").select { |image| %w[cover body].include?(image["role"]) }
        parts["D"] = mark(actual.css("img").map { |node| [ node["src"], node["alt"].to_s ] } == images.map { |image| image.values_at("url", "alt") })
        parts["E"] = image_files(images)
        parts["F"] = head(page, payload)
        faq = actual.css("[data-open-blog-faq-entry]").map do |entry|
          question = entry.at_css("h3")
          [ text(question), entry.css("p").map { |node| text(node) }.join(" ") ]
        end
        expected_faq = payload.fetch("faq").map { |entry| [ normalize(entry["question"]), normalize(entry["answer"]) ] }
        parts["G"] = mark(faq == expected_faq && (expected_faq.any? || actual.css("[data-open-blog-faq]").empty?))
        status = parts.value?("fail") ? :fail : parts.value?("not verified") ? :not_verified : :pass
        record("E19", status, status == :pass ? "Fetched content agrees with the stored public revision." : "Some revision comparisons differ or lack evidence.", post: post, details: parts)
      rescue JSON::ParserError, KeyError, ActionView::Template::Error => error
        record("E19", :not_verified, "Stored content could not be compared (#{error.class.name}).", post: post)
      end

      def image_files(images)
        results = images.map do |image|
          next "not verified" if image["sha256"].blank?
          page = image_page(image["url"])
          next "not verified" unless readable(page)
          mark(Digest::SHA256.hexdigest(page.body) == image["sha256"])
        end
        results.include?("fail") ? "fail" : results.include?("not verified") ? "not verified" : "pass"
      end

      def image_page(path)
        url = @context.absolute(path)
        seen = []
        6.times do
          return if url.nil? || seen.include?(url)
          seen << url
          page = @context.page(url)
          return page unless page && [ 301, 302, 303, 307, 308 ].include?(page.status)
          location = page.headers["location"] || page.headers["Location"]
          return if location.blank?
          url = URI.join(url, location).to_s
        end
        nil
      rescue URI::InvalidURIError, URI::BadURIError
        nil
      end

      def head(page, payload)
        document = page.document
        title = payload["search_title"].presence || payload["title"]
        description = payload["search_description"].presence || payload["description"]
        return "fail" unless document.at_css("title")&.text&.start_with?(title) && document.at_css('meta[name="description"]')&.[]("content") == description
        social = payload.fetch("images").select { |image| image["role"] == "social" }
        return "pass" if social.empty?
        url = document.at_css('meta[property="og:image"]')&.[]("content")
        return "fail" unless url && URI.parse(url).path == social.first["url"]
        image_files([ social.first.merge("url" => url) ])
      rescue URI::InvalidURIError
        "fail"
      end

      def notice(post)
        dependencies = [ @context.row("E4", post: post), @context.row("E18", post: post), @context.row("E19", post: post) ]
        needed = !post.provenance_human_written? && dependencies.any? { |row| !row || %w[fail].include?(row[:result].to_s) || row[:result].to_s.tr("_", " ") == "not verified" }
        return record("E20", :not_applicable, "The inspected evidence does not require an AI notice.", post: post) unless needed
        page = @context.post_page(post)
        return record("E20", :not_verified, "The article could not be inspected for a notice.", post: post) unless readable(page)
        key = post.provenance_ai_assisted? ? "ai_assisted" : "ai_unknown"
        label = I18n.t("open_blog.notices.#{key}", locale: @context.config.locale)
        valid = page.document.css(".ob-notice--ai").any? { |node| visible_text(node).include?(label) }
        record("E20", valid ? :pass : :fail, valid ? "The fetched article includes the relevant AI notice." : "The fetched article lacks the relevant AI notice.", post: post)
      end

      def connections(post)
        declaration = post.connection_declarations.order(:id).last
        page = @context.post_page(post)
        { "E21" => declaration && declaration.connections.any?, "E22" => declaration&.third_party_paid? }.each do |predicate, needed|
          if !declaration
            record(predicate, :not_verified, "No connection declaration was supplied.", post: post)
          elsif !needed
            record(predicate, :not_applicable, "The publisher declared no matching connection.", post: post)
          elsif !readable(page)
            record(predicate, :not_verified, "The article could not be inspected.", post: post)
          else
            selector = predicate == "E21" ? "[data-open-blog-content] .ob-disclosure" : "[data-open-blog-content] .ob-notice--paid"
            document = page.document
            valid = document.css(selector).any? do |node|
              next false if visible_text(node).blank?
              body = document.at_css("[data-open-blog-body]")
              predicate == "E21" || (body && (node <=> body) == -1)
            end
            record(predicate, valid ? :pass : :fail, valid ? "A disclosure is present in the article markup." : "A declared connection has no disclosure markup.", post: post)
          end
        end
      end

      def redirects
        entries = Redirect.all.to_a
        if entries.empty?
          began = Baseline.minimum(:adopted_at)
          reason = "No URL changes are recorded; earlier moves require imported history."
          reason += " Imported coverage begins #{began.iso8601}." if began
          return record("T4", :not_applicable, reason)
        end
        entries.each do |entry|
          page = @context.page(@context.absolute(entry.old_path))
          unless page && page.status.to_i.positive?
            record("T4", :not_verified, "The recorded old URL could not be fetched.", details: { path: entry.old_path })
            next
          end
          valid = if entry.new_path
            [ 301, 308 ].include?(page.status) && @context.absolute(page.headers["location"] || page.headers["Location"]) == @context.absolute(entry.new_path)
          else
            [ 404, 410 ].include?(page.status)
          end
          record("T4", valid ? :pass : :fail, valid ? "The old URL has the recorded response." : "The old URL differs from its recorded destination or removal.", details: { path: entry.old_path })
        end
      end

      def project(node)
        node = node.dup
        node.css(GENERATED).remove
        node
      end

      def visible_text(node)
        return "" unless node && ![ node, *node.ancestors ].any? { |parent| parent.key?("hidden") || parent["aria-hidden"] == "true" }
        text(node)
      end

      def text(node) = normalize(node&.text)
      def normalize(value) = value.to_s.gsub(/\s+/, " ").strip
      def links(node) = node.css("a[href]").map { |link| [ text(link), link["href"] ] }
      def mark(value) = value ? "pass" : "fail"

      def same_time?(value, expected)
        return false if value.blank?
        value = value.to_s
        value.length == 10 ? Date.iso8601(value) == expected.to_date : Time.iso8601(value).to_i == expected.to_i
      rescue ArgumentError
        false
      end
    end
  end
end
