xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.feed xmlns: "http://www.w3.org/2005/Atom" do
  xml.id "#{@base_url}#{OpenBlog.mount_path}"
  xml.title @feed_title
  xml.updated @feed_updated_at.iso8601
  xml.author { xml.name(OpenBlog.config.publisher&.fetch(:name, nil) || OpenBlog.config.site_name) }
  xml.link href: "#{@base_url}#{request.path}", rel: "self", type: "application/atom+xml"
  xml.link href: "#{@base_url}#{OpenBlog.mount_path}", rel: "alternate", type: "text/html"
  @posts.each do |post|
    xml.entry do
      xml.id post.url(base: @base_url)
      xml.title post.title
      xml.link href: post.url(base: @base_url), rel: "alternate", type: "text/html"
      xml.published OpenBlog::ReaderDates.published_at(post).iso8601 if OpenBlog::ReaderDates.published_at(post)
      xml.updated OpenBlog::ReaderDates.feed_updated_at(post).iso8601
      xml.author do
        xml.name post.author_name
        xml.uri "#{@base_url}#{OpenBlog::ReaderQueries.author_path(post.author)}"
      end
      if OpenBlog.config.feed_content == :full
        xml.content OpenBlog::Renderer.render(post), type: "html"
      else
        xml.summary post.description, type: "text"
      end
    end
  end
end
