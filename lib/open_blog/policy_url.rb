module OpenBlog
  class PolicyUrl
    def self.call(kind, config: OpenBlog.config)
      kind = kind.to_s
      return unless Page::KINDS.include?(kind)
      config.policy_urls[kind.to_sym].presence || Page.published.find_by(kind: kind)&.path
    end
  end
end
