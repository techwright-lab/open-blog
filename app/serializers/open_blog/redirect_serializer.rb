module OpenBlog
  class RedirectSerializer
    def self.call(record)
      { id: record.id, old_path: record.old_path, new_path: record.new_path, source: record.source, occurred_on: record.occurred_on, post_id: record.post_id }
    end
  end
end
