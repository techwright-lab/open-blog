module OpenBlog
  module Api
    module V1
      class ResourcesController < BaseController
        rescue_from ActiveRecord::RecordInvalid do |error|
          render_error(Error::ValidationFailed.new(details: error.record.errors.attribute_names.map(&:to_s)))
        end
        rescue_from ActiveRecord::RecordNotUnique do
          render_error(Error::ValidationFailed.new(details: [ "slug" ]))
        end

        private

        def list(relation, name, serializer)
          input = input_fields!(:page, :per_page)
          page = integer_parameter(input, :page, 1)
          per_page = [ integer_parameter(input, :per_page, 25), 100 ].min
          render json: { name => relation.order(:id).offset((page - 1) * per_page).limit(per_page).map { |record| serializer.call(record) },
            page: page, per_page: per_page, total: relation.count }
        end

        def integer_parameter(input, name, default)
          return default unless input.key?(name)
          value = input[name]
          invalid!(name) unless (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.match?(/\A[1-9]\d{0,8}\z/)
          value.to_i
        end

        def text_fields!(input, *fields)
          fields.each { |field| invalid!(field) if input.key?(field) && !input[field].nil? && !input[field].is_a?(String) }
        end

        def invalid!(field)
          raise Error::ValidationFailed.new(details: [ field.to_s ])
        end
      end
    end
  end
end
