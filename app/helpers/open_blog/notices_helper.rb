module OpenBlog
  module NoticesHelper
    def open_blog_notices(post)
      notices = []
      label = LabelPolicy.for(post)
      notices << tag.p(open_blog_translate("notices.#{label}"), class: "ob-notice ob-notice--ai") unless label == :none
      if open_blog_connection_declaration(post)&.third_party_paid?
        notices << tag.p(open_blog_translate("notices.paid"), class: "ob-notice ob-notice--paid")
      end
      safe_join(notices)
    end

    def open_blog_disclosure(post)
      declaration = open_blog_connection_declaration(post)
      return "".html_safe unless declaration
      content = if declaration.connections.empty?
        tag.p(open_blog_translate("notices.connections_none"))
      else
        tag.ul(safe_join(declaration.connections.map { |entry| tag.li("#{entry['party']}: #{entry['relation']}") }))
      end
      tag.aside(class: "ob-disclosure ob-notice", aria: { label: open_blog_translate("notices.disclosure") }) do
        safe_join([ tag.h2(open_blog_translate("notices.disclosure")), content ])
      end
    end

    def open_blog_corrections(post)
      rows = post.publications.where(entry_type: "correction").where("occurred_at <= ?", Time.current).order(:occurred_at, :id)
      safe_join(rows.map do |entry|
        tag.aside(class: "ob-correction ob-notice") do
          safe_join([ tag.strong(open_blog_translate("notices.correction")),
            tag.time(I18n.l(entry.occurred_at.to_date, format: :long, locale: OpenBlog.config.locale), datetime: entry.occurred_at.iso8601),
            tag.p(entry.note) ], " ")
        end
      end)
    end

    def open_blog_responsible_party_link
      url = OpenBlog.config.policy_urls[:responsible_party]
      return "".html_safe unless url.present? && Renderer::Sanitizer.safe_url?(url)
      link_to(open_blog_translate("navigation.responsible_party"), url, class: "ob-responsible-party")
    end

    def open_blog_connection_declaration(post)
      post.connection_declarations.order(id: :desc).first
    end
  end
end
