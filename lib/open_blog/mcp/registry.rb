module OpenBlog
  module Mcp
    module Registry
      module_function

      def definitions
        [
          endpoint("list_posts", :read, "posts", :index, fields: ApiFields::POST_LIST),
          endpoint("search_posts", :read, "posts", :index, fields: ApiFields::POST_LIST, required: [ :q ]),
          endpoint("get_post", :read, "posts", :show, id: :required),
          endpoint("get_post_records", :read, "records", :show, id: :required),
          endpoint("check_post", :read, "findings", :show, id: :required),
          endpoint("save_draft", :write, "posts", :create, fields: ApiFields::POST_WRITE, force: { publish: false }),
          endpoint("get_preview_link", :read, "previews", :show, id: :required),
          endpoint("publish_post", :publish, "posts", :publish, fields: ApiFields::POST_WRITE, id: :optional, create_publish: true),
          endpoint("update_post", :publish, "posts", :update, fields: ApiFields::POST_WRITE, id: :required),
          endpoint("correct_post", :publish, "posts", :update, fields: ApiFields::POST_WRITE, id: :required, required: [ :note ], force: { change: "correction" }),
          endpoint("approve_revision", :publish, "approvals", :create, fields: ApiFields::APPROVAL, id: :required, required: ApiFields::APPROVAL),
          endpoint("declare_connections", :publish, "connections", :create, fields: ApiFields::CONNECTION, id: :required,
            properties: Schemas.connection_fields, required: %i[connections third_party_paid declared_by]),
          endpoint("unpublish_post", :publish, "posts", :unpublish, id: :required),
          endpoint("remove_post", :publish, "posts", :destroy, fields: ApiFields::REMOVE, id: :required),
          upload_definition,
          endpoint("list_categories", :read, "categories", :index, fields: ApiFields::PAGE),
          endpoint("save_category", :write, "categories", :create, fields: ApiFields::CATEGORY, id: :optional, upsert: true),
          endpoint("list_tags", :read, "tags", :index, fields: ApiFields::PAGE),
          endpoint("list_authors", :read, "authors", :index, fields: ApiFields::PAGE),
          endpoint("save_author", :write, "authors", :create, fields: ApiFields::AUTHOR, id: :optional, upsert: true),
          endpoint("list_series", :read, "series", :index, fields: ApiFields::PAGE),
          endpoint("save_series", :write, "series", :create, fields: ApiFields::SERIES, id: :optional, upsert: true),
          endpoint("list_redirects", :read, "redirects", :index, fields: ApiFields::PAGE),
          endpoint("save_redirect", :publish, "redirects", :create, fields: ApiFields::REDIRECT, required: [ :old_path ]),
          site_page_definition("get_site_page", :read),
          site_page_definition("save_site_page", :write),
          page_views_definition,
          endpoint("doctor", :read, "doctor", :show),
          endpoint("extract_faq", :read, "faq_extractions", :create, fields: ApiFields::EXTRACTION, required: [ :body ]),
          endpoint("adopt_post", :publish, "adoptions", :create, fields: ApiFields::ADOPTION,
            required: %i[source_system source_id slug title body_format body])
        ]
      end

      def endpoint(name, scope, controller, action, fields: [], id: nil, required: [], force: {}, upsert: false, create_publish: false, properties: nil)
        properties ||= Schemas.fields(fields)
        properties = properties.merge("id" => upsert ? { type: "integer", minimum: 1 } : Schemas.identifier) if id
        required = required + (id == :required ? [ :id ] : [])
        force.each { |key, value| properties[key.to_s] = properties.fetch(key.to_s).merge(const: value) if properties.key?(key.to_s) }
        definition(name, scope, Schemas.object(properties, required: required)) do |arguments, actor:, base_url:|
          arguments = arguments.dup
          identity = arguments.delete(:id) if id
          selected = upsert && identity ? :update : action
          if create_publish && !identity
            selected = :create
            arguments[:publish] = true
          end
          arguments.merge!(force)
          if selected == :index
            maximum = [ OpenBlog.config.mcp.max_page_size, 100 ].min
            arguments[:per_page] = [ arguments.fetch(:per_page, 25).to_i, maximum ].min
          end
          method = { index: :get, show: :get, update: :patch, destroy: :delete }.fetch(selected, :post)
          Dispatcher.call(controller: controller, action: selected, method: method, arguments: arguments,
            actor: actor, route_params: identity ? { id: identity } : {}, base_url: base_url)
        end
      end

      def site_page_definition(name, scope)
        properties = name == "save_site_page" ? Schemas.fields(ApiFields::SITE_PAGE) : {}
        properties["kind"] = { type: "string", enum: %w[responsible_party corrections editorial ai_use] }
        if name == "save_site_page"
          properties["status"] = { type: "string", enum: %w[draft published] }
          %w[title body slug].each { |field| properties[field] = Schemas.text }
          %w[approved_by approved_on].each { |field| properties[field] = Schemas.text(nullable: true) }
        end
        definition(name, scope, Schemas.object(properties, required: [ :kind ])) do |arguments, actor:, base_url:|
          input = arguments.dup
          kind = input.delete(:kind)
          writing = name == "save_site_page"
          Dispatcher.call(controller: "pages", action: writing ? :update : :show, method: writing ? :put : :get,
            arguments: input, actor: actor, route_params: { kind: kind }, base_url: base_url)
        end
      end

      def page_views_definition
        properties = { "id" => Schemas.identifier }
        ApiFields::VIEWS.each { |field| properties[field.to_s] = Schemas.text(nullable: true) }
        ApiFields::TOP_VIEWS.each do |field|
          maximum = field == :days ? 36500 : 100
          properties[field.to_s] = { anyOf: [ { type: "integer", minimum: 1, maximum: maximum }, { type: "string", pattern: "^[1-9][0-9]*$" } ] }
        end
        schema = Schemas.object(properties).merge(oneOf: [
          { required: [ "id" ], not: { anyOf: [ { required: [ "days" ] }, { required: [ "limit" ] } ] } },
          { not: { anyOf: [ { required: [ "id" ] }, { required: [ "from" ] }, { required: [ "to" ] } ] } }
        ])
        definition("get_page_views", :read, schema) do |arguments, actor:, base_url:|
          input = arguments.dup
          id = input.delete(:id)
          Dispatcher.call(controller: "views", action: id ? :show : :top, method: :get, arguments: input,
            actor: actor, route_params: id ? { post_id: id } : {}, base_url: base_url)
        end
      end

      def upload_definition
        properties = Schemas.fields(%i[url filename content_type]).merge("base64" => Schemas.text)
        schema = Schemas.object(properties).merge(oneOf: [ { required: [ "url" ], maxProperties: 1 }, { required: %w[base64 filename content_type], maxProperties: 3 } ])
        definition("upload_image", :write, schema) do |arguments, actor:, base_url:|
          ImageInput.with_upload(arguments) do |input|
            Dispatcher.call(controller: "images", action: :create, method: :post, arguments: input, actor: actor, route_params: {}, base_url: base_url)
          end
        end
      end

      def definition(name, scope, schema, &handler)
        instruction = if name == "adopt_post"
          OpenBlog::ADOPTION_INSTRUCTION
        elsif %w[publish_post update_post correct_post approve_revision].include?(name)
          "#{OpenBlog::APPROVAL_INSTRUCTION} #{OpenBlog::PROVENANCE_INSTRUCTION}"
        else
          OpenBlog::APPROVAL_POINTER
        end
        instruction += " #{OpenBlog::DRAFT_INSTRUCTION}" if name == "save_draft"
        description = "#{name.tr('_', ' ').capitalize}. #{instruction}"
        Definition.new(name: "blog_#{name}", title: name.tr("_", " ").capitalize, description: description,
          input_schema: schema, annotations: { read_only_hint: scope == :read, destructive_hint: name == "remove_post" },
          scope: scope, handler: handler)
      end
    end
  end
end
