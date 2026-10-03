module OpenBlog
  class AdoptionResultSerializer
    def self.call(result, base_url: nil)
      { post: PostSerializer.call(result.post, base_url: base_url, label: result.label), created: result.created,
        records: result.records.slice(:revision, :publication, :approval, :baseline, :redirects),
        findings: FindingsSerializer.entries(result.findings), dry_run: result.dry_run }
    end
  end
end
