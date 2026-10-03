require_relative "findings/check"
require_relative "findings/registry"
require_relative "findings/record_checks"
require_relative "findings/body_checks"
require_relative "findings/link_check"

module OpenBlog
  module Findings
    class << self
      def registry
        @registry ||= Registry.new.tap do |registry|
          RecordChecks.build.each { |check| registry.register(check) }
          BodyChecks.build.each { |check| registry.register(check) }
          registry.register(LinkCheck.new)
        end
      end

      def register(check)
        registry.register(check)
      end

      def for(post, context: {})
        registry.for(post, context: context.dup)
      end
    end
  end
end
