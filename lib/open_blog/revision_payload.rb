require "digest"
require "json"

module OpenBlog
  class RevisionPayload
    VERSION = "1".freeze

    def self.from_fields(title:, description:, search_title:, search_description:, body:, author:, images:, faq:)
      new(nil, title: title, description: description, search_title: search_title,
        search_description: search_description, body: body, author: author, images: images, faq: faq)
    end

    def initialize(post, **fields)
      fields = fields_from_post(post) if post
      @payload = {
        "author" => normalize(fields[:author]),
        "body" => normalize(fields[:body], body: true),
        "description" => normalize(fields[:description]),
        "faq" => fields.fetch(:faq).map { |entry| normalized_entry(entry, %w[answer question]) },
        "images" => fields.fetch(:images).map { |entry| normalized_entry(entry, %w[alt role sha256 url]) },
        "search_description" => normalize(fields[:search_description]),
        "search_title" => normalize(fields[:search_title]),
        "title" => normalize(fields[:title]),
        "version" => VERSION
      }
    end

    def to_h
      @payload
    end

    def to_json(*)
      JSON.generate(@payload, ascii_only: false, script_safe: false)
    end

    def identifier
      Digest::SHA256.hexdigest(to_json)
    end

    private

    def fields_from_post(post)
      images = []
      images << image_entry(post.cover_image, "cover", post.cover_alt) if post.cover_image
      images.concat(Renderer.body_images(post))
      images << image_entry(post.social_image, "social", "") if post.social_image
      {
        title: post.title, description: post.description, search_title: post.search_title,
        search_description: post.search_description, body: post.body_for_payload,
        author: post.author_name, images: images, faq: post.faq_list
      }
    end

    def image_entry(image, role, alt)
      { role: role, url: image.path, sha256: image.sha256, alt: alt }
    end

    def normalized_entry(entry, keys)
      keys.to_h { |key| [ key, normalize(entry.key?(key) ? entry[key] : entry[key.to_sym]) ] }
    end

    def normalize(value, body: false)
      text = value.to_s.encode(Encoding::UTF_8).unicode_normalize(:nfc).gsub(/\r\n?/, "\n")
      body ? text.sub(/\n+\z/, "") : text.gsub(/\A[ \t\n]+|[ \t\n]+\z/, "")
    end
  end
end
