module OpenBlog
  module Findings
    class Check
      attr_reader :code

      def initialize(code:, rule:, message:, location: nil, &predicate)
        @code, @rule, @message, @location, @predicate = code, rule, message, location, predicate
      end

      def call(post, context: {})
        matched = @predicate.call(post, context)
        return [] unless matched

        location = @location.respond_to?(:call) ? @location.call(post, context, matched) : @location
        [ { code: code, rule: @rule, message: @message, location: location } ]
      end
    end
  end
end
