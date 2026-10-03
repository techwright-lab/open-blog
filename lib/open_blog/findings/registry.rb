module OpenBlog
  module Findings
    class Registry
      def initialize
        @checks = {}
      end

      def register(check)
        @checks[check.code] = check
        self
      end

      def for(post, context: {})
        @checks.values.flat_map { |check| check.call(post, context: context) }
      end
    end
  end
end
