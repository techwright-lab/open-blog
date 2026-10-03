module OpenBlog
  module Api
    module V1
      class ConnectionsController < BaseController
        def create
          require_scope!(:publish)
          input = input_fields!(*ApiFields::CONNECTION)
          validate_input!(input)
          now = Time.current
          result = Operation.run(post: find_post!, actor: actor.name, now: now) do |post, _created|
            post.connection_declarations.create!(input.merge(declared_on: input.fetch(:declared_on, now.to_date), recorded_by: actor.name))
            { revision: nil, publication: nil, approval: nil }
          end
          render_result(result, status: :ok)
        end

        private

        def validate_input!(input)
          invalid!(:connections) unless input[:connections].is_a?(Array)
          input[:connections].each do |entry|
            invalid!(:connections) unless entry.is_a?(Hash)
            unknown = entry.keys - %i[party relation]
            raise Error::UnknownField.new(details: unknown.map { |key| "connections.#{key}" }) if unknown.any?
            invalid!(:connections) unless %i[party relation].all? { |key| entry[key].is_a?(String) && entry[key].present? }
          end
          invalid!(:third_party_paid) unless [ true, false ].include?(input[:third_party_paid])
          invalid!(:declared_by) unless input[:declared_by].is_a?(String) && input[:declared_by].present?
          if input.key?(:declared_on)
            invalid!(:declared_on) unless input[:declared_on].is_a?(String) && input[:declared_on].match?(/\A\d{4}-\d{2}-\d{2}\z/)
            begin
              input[:declared_on] = Date.iso8601(input[:declared_on])
            rescue Date::Error
              invalid!(:declared_on)
            end
          end
        end

        def invalid!(field)
          raise Error::ValidationFailed.new(details: [ field.to_s ])
        end
      end
    end
  end
end
