require_relative "findings/check"
require_relative "findings/registry"
require_relative "findings/record_checks"
require_relative "findings/body_checks"

module OpenBlog
  module Findings
    class << self
      def registry
        @registry ||= Registry.new.tap do |registry|
          RecordChecks.build.each { |check| registry.register(check) }
          BodyChecks.build.each { |check| registry.register(check) }
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
