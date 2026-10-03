module OpenBlog
  class ImageSerializer
    def self.call(image)
      return unless image
      { image_id: image.id, url: image.path, sha256: image.sha256, filename: image.filename,
        content_type: image.content_type, byte_size: image.byte_size, width: image.width, height: image.height }
    end
  end
end
