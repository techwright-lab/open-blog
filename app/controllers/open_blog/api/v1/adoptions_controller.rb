module OpenBlog
  module Api
    module V1
      class AdoptionsController < BaseController
        def create
          require_scope!(:publish)
          attributes = input_fields!(*(Adopt::Contract::CONTENT_FIELDS + Adopt::Contract::EXTRA_FIELDS))
          PostsController::NESTED_FIELDS.except(:approval, :connections).each do |field, allowed|
            values = field == :faq && attributes[field].is_a?(Array) ? attributes[field] : [ attributes[field] ]
            values.each do |value|
              next unless value.is_a?(Hash)
              unknown = value.keys - allowed
              raise Error::UnknownField.new(details: unknown.map { |key| "#{field}.#{key}" }) if unknown.any?
            end
          end
          if attributes.key?(:author) && !attributes[:author].is_a?(String) && !attributes[:author].is_a?(Hash)
            raise Error::ValidationFailed.new(details: [ "author" ])
          end
          result = Adopt.call(attributes, actor: actor.name)
          return render_error(result.error) unless result.success?
          render json: AdoptionResultSerializer.call(result, base_url: request.base_url), status: result.created ? :created : :ok
        end
      end
    end
  end
end
