module OpenBlog
  module Mcp
    class Definition
      attr_reader :name, :title, :description, :input_schema, :annotations, :scope

      def initialize(name:, title:, description:, input_schema:, annotations:, scope:, handler:)
        @name, @title, @description = name, title, description
        @input_schema, @annotations, @scope, @handler = input_schema, annotations, scope, handler
        @validator = ::MCP::Tool::InputSchema.new(input_schema)
      end

      def call(arguments, actor:, base_url: nil)
        raise Error::Unauthenticated unless actor
        unless actor.respond_to?(:scopes) && actor.scopes.map(&:to_s).include?(scope.to_s)
          raise Error::ScopeRequired.new(details: [ scope.to_s ])
        end
        raise Error::ValidationFailed.new(details: [ "arguments" ]) unless arguments.is_a?(Hash)
        @validator.validate_arguments(arguments)
        result = @handler.call(arguments.deep_symbolize_keys, actor: actor, base_url: base_url)
        JSON.parse(JSON.generate(result))
      rescue ::MCP::Tool::InputSchema::ValidationError
        JSON.parse(JSON.generate(ErrorSerializer.call(Error::ValidationFailed.new(details: [ "arguments" ]))))
      rescue Error => error
        JSON.parse(JSON.generate(ErrorSerializer.call(error)))
      end
    end
  end
end
