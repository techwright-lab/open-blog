module OpenBlog
  class MarkdownView
    def self.render(post, base_url: OpenBlog.config.public_base_url, now: Time.current)
      new(post, base_url: base_url, now: now).render
    end

    def initialize(post, base_url:, now:)
      @post, @base_url, @now = post, base_url, now
    end

    def render
      parts = [ "# #{plain(@post.title)}", plain(@post.description).presence, byline, *notices, body ]
      entries = @post.faq_list
      if entries.any?
        parts << "## #{plain(translate('faq.heading'))}"
        entries.each { |entry| parts.concat([ "### #{plain(entry[:question])}", plain(entry[:answer]) ]) }
      end
      parts << (@post.canonical_url.presence || @post.url(base: @base_url) || @post.path)
      "#{parts.compact.join("\n\n")}\n"
    end

    private

    def body
      @post.markdown? ? @post.body_markdown.to_s : plain(@post.rich_body.to_plain_text)
    end

    def byline
      published = ReaderDates.published_at(@post, now: @now)
      modified = ReaderDates.modified_at(@post, now: @now)
      parts = [ @post.author_name ]
      parts << date(published, :published) if published
      parts << date(modified, :updated) if modified && (!published || modified > published)
      plain(parts.join(" · "))
    end

    def date(time, label)
      "#{translate("dates.#{label}")} #{I18n.l(time.to_date, format: :long, locale: OpenBlog.config.locale)}"
    end

    def notices
      label = LabelPolicy.for(@post)
      lines = label == :none ? [] : [ translate("notices.#{label}") ]
      lines << translate("notices.paid") if @post.connection_declarations.order(id: :desc).first&.third_party_paid?
      lines.map { |line| plain(line) }
    end

    def translate(key)
      I18n.t("open_blog.#{key}", locale: OpenBlog.config.locale)
    end

    def plain(text)
      text.to_s.gsub(/[\\`*_{}\[\]<>&!#|~+\-]/) { |character| "\\#{character}" }
        .gsub(/^(\s*\d+)([.)])(?=\s)/) { "#{Regexp.last_match(1)}\\#{Regexp.last_match(2)}" }
    end
  end
end
