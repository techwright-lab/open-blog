module OpenBlog
  module StructuredDataHelper
    def open_blog_structured_data(resource = nil)
      page = open_blog_page(resource)
      graph = [ open_blog_page_schema(page), open_blog_breadcrumb_schema(page) ]
      if %i[post preview].include?(page.kind) && (entries = page.record.faq_list).any?
        graph << { "@type" => "FAQPage", "mainEntity" => entries.map do |entry|
          { "@type" => "Question", "name" => entry[:question],
            "acceptedAnswer" => { "@type" => "Answer", "text" => entry[:answer] } }
        end }
      end
      json = ERB::Util.json_escape({ "@context" => "https://schema.org", "@graph" => graph }.to_json)
      tag.script(json.html_safe, type: "application/ld+json")
    end

    def open_blog_page_schema(page)
      case page.kind
      when :post, :preview
        post = page.record
        publisher = OpenBlog.config.publisher || {}
        data = { "@type" => "BlogPosting", "headline" => post.title, "description" => post.description.to_s,
          "author" => open_blog_author_schema(post.author, name: post.author_name, base: page.base_url),
          "publisher" => { "@type" => "Organization", "name" => publisher[:name], "url" => publisher[:url] }.compact,
          "mainEntityOfPage" => open_blog_canonical_url(page), "wordCount" => post.word_count,
          "keywords" => post.tags.map(&:name), "articleSection" => post.category&.name }
        if publisher[:logo_url].present?
          data["publisher"]["logo"] = { "@type" => "ImageObject", "url" => publisher[:logo_url] }
        end
        published, modified = ReaderDates.published_at(post), ReaderDates.modified_at(post)
        data["datePublished"] = published.iso8601 if published
        data["dateModified"] = modified.iso8601 if modified
        image = open_blog_social_image_url(page)
        data["image"] = image if image
        data.compact
      when :page
        { "@type" => "WebPage", "name" => page.record.title, "description" => open_blog_page_description(page),
          "url" => open_blog_canonical_url(page), "dateModified" => page.record.updated_at.iso8601 }
      when :author
        { "@type" => "ProfilePage", "name" => page.record.name, "url" => open_blog_canonical_url(page),
          "mainEntity" => open_blog_author_schema(page.record, base: page.base_url) }
      else
        posts = page.pagination&.records || []
        { "@type" => page.kind == :index ? "Blog" : "CollectionPage", "name" => open_blog_page_title(page),
          "description" => open_blog_page_description(page), "url" => open_blog_canonical_url(page),
          "mainEntity" => { "@type" => "ItemList", "itemListElement" => posts.each_with_index.map do |post, index|
            { "@type" => "ListItem", "position" => index + 1, "url" => post.url(base: page.base_url), "name" => post.title }
          end } }
      end
    end

    def open_blog_author_schema(author, name: author.name, base: nil)
      { "@type" => author.author_type == "organization" ? "Organization" : "Person", "name" => name,
        "url" => open_blog_absolute_url(open_blog_list_path(:author, author), base: base) }
    end

    def open_blog_breadcrumb_schema(page)
      { "@type" => "BreadcrumbList", "itemListElement" => page.breadcrumbs.each_with_index.map do |crumb, index|
        { "@type" => "ListItem", "position" => index + 1, "name" => crumb[:name],
          "item" => open_blog_absolute_url(crumb[:path], base: page.base_url) }
      end }
    end
  end
end
