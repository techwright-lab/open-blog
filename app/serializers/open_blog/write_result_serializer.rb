module OpenBlog
  class WriteResultSerializer
    def self.call(result, base_url: nil)
      { post: PostSerializer.call(result.post, base_url: base_url), created: result.created,
        records: result.records.slice(:revision, :publication, :approval), label: result.label.to_s,
        findings: FindingsSerializer.entries(result.findings) }
    end
  end
end
