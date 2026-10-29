require "json"

module OpenBlog
  module ApiTokens
    class Secret
      FILTERED = "[FILTERED]".freeze

      def initialize(value)
        @value = value.dup.freeze
      end

      def reveal
        @value
      end

      def to_s
        FILTERED
      end

      def inspect
        FILTERED
      end

      def as_json(*)
        FILTERED
      end

      def to_json(*)
        FILTERED.to_json
      end
    end
  end
end
