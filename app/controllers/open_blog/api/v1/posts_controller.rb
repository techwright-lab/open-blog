module OpenBlog
  module Api
    module V1
      class PostsController < BaseController
        WRITE_FIELDS = (PostAttributes::CONTENT_FIELDS + PostAttributes::RECORD_FIELDS).freeze
        NESTED_FIELDS = {
          author: %i[name type url], approval: %i[name facts_checked revision_identifier],
          cover_image: %i[image_id signed_id url], social_image: %i[image_id signed_id url],
          connections: %i[connections third_party_paid declared_by declared_on], faq: %i[question answer]
        }.freeze

        def index
          require_scope!(:read)
          render json: ApiPostQuery.call(input_fields!(*ApiPostQuery::FILTERS), base_url: request.base_url)
        end

        def show
          require_scope!(:read)
          input_fields!
          render json: PostSerializer.call(find_post!, base_url: request.base_url)
        end

        def create
          attributes = write_attributes(publish_field: true)
          publishing = attributes.delete(:publish) == true
          operation = publishing ? Publish : SaveDraft
          render_result operation.call(attributes, actor: actor.name, authorize: authorization(publishing: publishing))
        end

        def update
          attributes = write_attributes
          result = WritePost.call(attributes, post: find_post!, actor: actor.name, now: Time.current,
            publish: :preserve, authorize: authorization)
          render_result(result, status: :ok)
        end

        def publish
          require_scope!(:publish)
          render_result Publish.call(write_attributes, post: find_post!, actor: actor.name,
            authorize: authorization(publishing: true))
        end

        def unpublish
          require_scope!(:publish)
          input_fields!
          render_result Unpublish.call(find_post!, actor: actor.name)
        end

        def destroy
          require_scope!(:publish)
          attributes = input_fields!(:redirect_to)
          if attributes[:redirect_to].is_a?(String) && attributes[:redirect_to].match?(Post::SLUG_PATTERN)
            attributes[:redirect_to] = "#{OpenBlog.mount_path.chomp('/')}/#{attributes[:redirect_to]}"
          end
          result = Remove.call(find_post!, actor: actor.name, **attributes)
          if result.success? && result.post.destroyed?
            head :no_content
          else
            render_result(result, status: :ok)
          end
        end

        private

        def authorization(publishing: false)
          ->(post) { require_scope!(publishing || post.scheduled? || post.published? ? :publish : :write) }
        end

        def write_attributes(publish_field: false)
          attributes = input_fields!(*(publish_field ? WRITE_FIELDS + [ :publish ] : WRITE_FIELDS))
          if attributes.key?(:publish) && ![ true, false ].include?(attributes[:publish])
            raise Error::ValidationFailed.new(details: [ "publish" ])
          end
          if attributes.key?(:author) && !attributes[:author].is_a?(String) && !attributes[:author].is_a?(Hash)
            raise Error::ValidationFailed.new(details: [ "author" ])
          end
          NESTED_FIELDS.each do |field, allowed|
            values = field == :faq && attributes[field].is_a?(Array) ? attributes[field] : [ attributes[field] ]
            values.each do |value|
              next unless value.is_a?(Hash)
              unknown = value.keys - allowed
              raise Error::UnknownField.new(details: unknown.map { |key| "#{field}.#{key}" }) if unknown.any?
            end
          end
          connections = attributes.dig(:connections, :connections) if attributes[:connections].is_a?(Hash)
          if connections.is_a?(Array)
            connections.each do |entry|
              next unless entry.is_a?(Hash)
              unknown = entry.keys - %i[party relation]
              raise Error::UnknownField.new(details: unknown.map { |key| "connections.connections.#{key}" }) if unknown.any?
            end
          end
          validate_connections!(attributes[:connections]) if attributes.key?(:connections)
          attributes
        end

        def validate_connections!(input)
          invalid = -> { raise Error::ValidationFailed.new(details: [ "connections" ]) }
          invalid.call unless input.is_a?(Hash) && input[:connections].is_a?(Array)
          invalid.call unless input[:declared_by].is_a?(String) && input[:declared_by].present?
          input[:connections].each do |entry|
            invalid.call unless entry.is_a?(Hash) && %i[party relation].all? { |key| entry[key].is_a?(String) && entry[key].present? }
          end
          if input.key?(:declared_on)
            value = input[:declared_on]
            invalid.call unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
            begin
              input[:declared_on] = Date.iso8601(value)
            rescue Date::Error
              invalid.call
            end
          end
        end
      end
    end
  end
end
