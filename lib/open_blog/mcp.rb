module OpenBlog
  module Mcp
    autoload :Definition, "open_blog/mcp/definition"
    autoload :Dispatcher, "open_blog/mcp/dispatcher"
    autoload :Registry, "open_blog/mcp/registry"
    autoload :Schemas, "open_blog/mcp/schemas"
    autoload :ImageInput, "open_blog/mcp/image_input"

    def self.definitions
      Registry.definitions
    end

    def self.tools
      definitions.map do |definition|
        ::MCP::Tool.define(name: definition.name, title: definition.title, description: definition.description,
          input_schema: definition.input_schema, annotations: definition.annotations) do |server_context: nil, **arguments|
          result = definition.call(arguments, actor: server_context&.[](:actor), base_url: server_context&.[](:base_url))
          ::MCP::Tool::Response.new([ { type: "text", text: JSON.generate(result) } ],
            structured_content: result, error: result.key?("error"))
        end
      end
    end
  end
end
