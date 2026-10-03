module OpenBlog
  module Mcp
    module Schemas
      module_function

      def object(properties, required: [])
        { type: "object", properties: properties, required: required.map(&:to_s), additionalProperties: false }
      end

      def text(nullable: false)
        { type: nullable ? [ "string", "null" ] : "string" }
      end

      def identifier
        { anyOf: [ { type: "integer", minimum: 1 }, { type: "string", minLength: 1 } ] }
      end

      def fields(names)
        names.to_h { |name| [ name.to_s, field(name) ] }
      end

      def field(name)
        case name.to_sym
        when :id then identifier
        when :featured, :facts_checked, :third_party_paid, :dry_run then { type: "boolean" }
        when :made_by_ai then { type: [ "boolean", "null" ] }
        when :position then { type: "integer", minimum: -2_147_483_648, maximum: 2_147_483_647 }
        when :series_position, :post_id then { type: [ "integer", "null" ], minimum: 1 }
        when :page, :per_page
          { anyOf: [ { type: "integer", minimum: 1, maximum: 999_999_999 }, { type: "string", pattern: "^[1-9][0-9]{0,8}$" } ] }
        when :tags, :profile_urls, :standalone_questions then { type: "array", items: text }
        when :faq then { type: "array", items: object(fields(ApiFields::POST_NESTED.fetch(:faq)), required: %w[question answer]) }
        when :author
          { anyOf: [ text, object(fields(ApiFields::POST_NESTED.fetch(:author)), required: [ "name" ]) ] }
        when :cover_image, :social_image, :avatar
          { anyOf: [ { type: "null" }, image ] }
        when :approval
          object(fields(ApiFields::POST_NESTED.fetch(:approval)), required: %w[name facts_checked])
        when :connections
          object(connection_fields, required: %w[connections third_party_paid declared_by])
        when :declaration
          object(fields(%i[reviewer_name approved_at facts_checked declared_on declared_by declared_first_published_at]), required: %w[reviewer_name approved_at facts_checked declared_on declared_by])
        when :imported_approval
          object(fields(%i[reviewer_name approved_at facts_checked evidence confirmed_by]), required: %w[reviewer_name approved_at facts_checked evidence confirmed_by])
        when :old_slugs
          { type: "array", items: { anyOf: [ text, object(fields(%i[slug moved_on]), required: [ "slug" ]) ] } }
        when :image_id then { type: "integer", minimum: 1 }
        when :type then { type: "string", enum: %w[person organization] }
        when :body_format then { type: "string", enum: %w[markdown rich_text] }
        when :provenance then { type: "string", enum: %w[ai_assisted human_written unknown] }
        when :change then { type: "string", enum: %w[substantive correction maintenance] }
        when :status then { type: "string", enum: %w[draft scheduled published archived] }
        when :body, :description, :search_title, :search_description, :canonical_url, :cover_alt, :external_id,
            :category, :series, :provenance_evidence, :publish_at, :first_published_at, :last_modified_at,
            :first_published_evidence, :last_modified_evidence, :declared_first_published_at, :source_body_sha256,
            :bio, :url, :host_reference, :new_path, :redirect_to, :moved_on
          text(nullable: true)
        else text
        end
      end

      def connection_fields
        fields(ApiFields::CONNECTION - [ :connections ]).merge("connections" => { type: "array",
          items: object(fields(%i[party relation]), required: %w[party relation]) })
      end

      def image
        object(fields(%i[image_id signed_id url])).merge(minProperties: 1, maxProperties: 1)
      end
    end
  end
end
