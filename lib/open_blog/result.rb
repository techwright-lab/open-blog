module OpenBlog
  Result = Data.define(:post, :created, :records, :label, :findings, :error, :dry_run) do
    def initialize(post: nil, created: false, records: { revision: nil, publication: nil, approval: nil }, label: :ai_unknown, findings: [], error: nil, dry_run: false)
      super
    end

    def success?
      error.nil?
    end
  end
end
