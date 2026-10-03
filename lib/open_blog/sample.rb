require "digest"
require "stringio"

module OpenBlog
  class Sample
    EXTERNAL_ID = "open_blog_sample".freeze
    ASSETS = File.expand_path("../generators/open_blog/install/templates", __dir__).freeze

    def self.call
      new.call
    end

    def call
      existing = Post.find_by(external_id: EXTERNAL_ID)
      return existing if existing

      Post.transaction(requires_new: true) do
        image = cover
        markdown = File.read(File.join(ASSETS, "sample_post.md")).gsub("{{sample_image}}", image.path)
        format = OpenBlog.config.default_body_format
        body = format.to_s == "rich_text" ? rich_text(markdown) : markdown
        result = Publish.call({ external_id: EXTERNAL_ID, title: "A small guide to your new blog",
          slug: "open-blog-sample", description: "Explore headings, images, code and reader questions in this sample article.",
          body: body, body_format: format, category: "General", provenance: "ai_assisted",
          cover_image: image, cover_alt: "Blue and green blocks arranged as a simple landscape",
          faq: [ { question: "Can I edit this sample?", answer: "Yes. Replace it with your own article, or remove it when you are ready." },
            { question: "Will running the sample task create another copy?", answer: "No. Running the task again keeps the existing sample and its content." } ] },
          post: Post.new, actor: "OpenBlog sample")
        raise result.error unless result.success?
        result.post
      end.tap { @completed = true }
    ensure
      @uploaded_blob.service.delete(@uploaded_blob.key) if @uploaded_blob && !@completed
    end

    private

    def rich_text(markdown)
      document = Nokogiri::HTML5.fragment(Renderer::Markdown.render(markdown))
      # Rich text removes source IDs. Keep footnote text without broken links.
      document.css("a[data-footnote-ref]").each { |link| link.replace(link.children) }
      document.css("a[data-footnote-backref]").remove
      document.to_html
    end

    def cover
      bytes = File.binread(File.join(ASSETS, "sample_cover.png"))
      existing = Image.find_by(sha256: Digest::SHA256.hexdigest(bytes))
      return existing if existing
      @uploaded_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "sample-cover.png",
        content_type: "image/png", identify: false,
        service_name: OpenBlog.config.storage_service || Rails.application.config.active_storage.service)
      ImageImport.prepare(signed_id: @uploaded_blob.signed_id).persist(uploaded_by: "OpenBlog sample")
    end
  end
end
