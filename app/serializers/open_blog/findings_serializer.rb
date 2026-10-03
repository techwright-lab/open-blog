module OpenBlog
  class FindingsSerializer
    def self.call(findings)
      { findings: entries(findings) }
    end

    def self.entries(findings)
      findings.map do |finding|
        { code: finding[:code], rule: finding[:rule], message: finding[:message], location: finding[:location] }
      end
    end
  end
end
