module OpenBlog
  module ContentHelper
    include FaqHelper

    def open_blog_post_content(_post, &block)
      tag.article(class: "ob-post-content", data: { open_blog_content: true }, &block)
    end

    def open_blog_title(post)
      tag.h1(post.title, class: "ob-post-title")
    end

    def open_blog_byline(post)
      tag.div(class: "ob-byline") do
        safe_join([ link_to(post.author_name, open_blog_list_path(:author, post.author), class: "ob-byline-author"), open_blog_dates(post) ], " ")
      end
    end

    def open_blog_cover(post)
      return "".html_safe unless post.cover_image
      image = post.cover_image
      tag.figure(class: "ob-cover") do
        tag.img(src: image.path, alt: post.cover_alt.to_s, width: image.width, height: image.height)
      end
    end

    def open_blog_card_image(post)
      image = post.cover_image
      return tag.div(class: "ob-card-placeholder", aria: { hidden: true }) unless image
      source = image.file.attached? ? main_app.url_for(image.file.variant(resize_to_fill: [ 640, 360 ])) : image.path
      tag.img(src: source, alt: post.cover_alt.to_s, width: 640, height: 360, loading: "lazy", class: "ob-card-image")
    end

    def open_blog_avatar(author, name: nil)
      name ||= author.name
      if author.avatar.attached?
        tag.img(src: main_app.url_for(author.avatar.variant(resize_to_fill: [ 80, 80 ])), alt: name, width: 40, height: 40, class: "ob-avatar", loading: "lazy")
      else
        tag.span(name.to_s.chars.first(2).join.upcase, class: "ob-avatar ob-avatar--initials", aria: { hidden: true })
      end
    end

    def open_blog_body(post)
      tag.div(Renderer.render(post, cache: @open_blog_page&.kind != :preview), class: "ob-prose", data: { open_blog_body: true })
    end

    def open_blog_reading_time(post)
      tag.span(open_blog_translate("reading_time", count: post.reading_time_minutes || 1), class: "ob-reading-time")
    end

    def open_blog_toc(post)
      fragment = Nokogiri::HTML5.fragment(Renderer.render(post, cache: @open_blog_page&.kind != :preview))
      headings = fragment.css("h2, h3")
      has_faq = post.faq_list.any?
      return "".html_safe if headings.length + (has_faq ? 1 : 0) < 3
      items = headings.map do |heading|
        text = heading.dup
        text.css(".ob-heading-anchor").remove
        tag.li(link_to(text.text, "##{heading['id']}"), class: "ob-toc-item ob-toc-item--#{heading.name}")
      end
      if has_faq
        items << tag.li(link_to(open_blog_translate("faq.heading"), "##{open_blog_faq_section_id(post, body: fragment)}"), class: "ob-toc-item ob-toc-item--h2")
      end
      tag.nav(class: "ob-toc", aria: { label: open_blog_translate("navigation.toc") }, data: { controller: "open-blog--toc" }) do
        safe_join([ tag.h2(open_blog_translate("navigation.toc")), tag.ol(safe_join(items)) ])
      end
    end

    def open_blog_breadcrumbs(page = nil)
      page = open_blog_page(page)
      tag.nav(class: "ob-breadcrumbs", aria: { label: open_blog_translate("navigation.breadcrumbs") }) do
        tag.ol(safe_join(page.breadcrumbs.each_with_index.map do |crumb, index|
          last = index == page.breadcrumbs.length - 1
          tag.li(last ? tag.span(crumb[:name], aria: { current: "page" }) : link_to(crumb[:name], crumb[:path]))
        end))
      end
    end
  end
end
