module OpenBlog
  class ExtractionResultSerializer
    def self.call(result)
      result.slice(:pairs, :cut, :body_after, :leftover, :class, :reasons, :source_body_sha256)
    end
  end
end
