module OpenBlog
  module Api
    module V1
      class BaseController < ActionController::API
        include ActionController::HttpAuthentication::Token::ControllerMethods
        before_action :prevent_caching!
        before_action :authenticate!
        before_action :limit_requests!
        wrap_parameters false

        rescue_from OpenBlog::Error, with: :render_error
        rescue_from ActiveRecord::RecordNotFound do
          render_error(Error::NotFound.new)
        end
        rescue_from ActionDispatch::Http::Parameters::ParseError, ActionController::BadRequest do
          render_error(Error::ValidationFailed.new(details: [ "body" ]))
        end

        # Rails 8.0 has no limiter scope keyword. Only the exact current API
        # controller prefix is replaced; all other cache keys pass through.
        class SharedLimitStore
          def initialize(store, controller_path)
            @store = store
            @prefix = "rate-limit:#{controller_path}:"
          end

          def increment(key, amount, **options)
            normalized = key.start_with?(@prefix) ? "rate-limit:open_blog/api:#{key.delete_prefix(@prefix)}" : key
            @store.increment(normalized, amount, **options)
          end
        end

        private

        attr_reader :actor

        def prevent_caching!
          response.headers["Cache-Control"] = "no-store"
        end

        def authenticate!
          @actor = Authentication.actor_for(request)
          raise Error::Unauthenticated unless actor
        end

        def require_scope!(scope)
          raise Error::ScopeRequired.new(details: [ scope.to_s ]) unless actor.scopes.include?(scope.to_s)
        end

        def limit_requests!
          options = { to: OpenBlog.config.api_rate_limit.fetch(:to), within: OpenBlog.config.api_rate_limit.fetch(:within),
            by: -> { actor.id }, with: -> { raise Error::RateLimited }, store: OpenBlog.config.rate_limit_store, name: nil }
          if method(:rate_limiting).parameters.any? { |kind, name| kind == :keyreq && name == :scope }
            options[:scope] = "open_blog/api"
          else
            options[:store] = SharedLimitStore.new(options[:store], controller_path)
          end
          rate_limiting(**options)
        end

        def input_fields!(*allowed)
          input = request.query_parameters.merge(request.request_parameters)
          unknown = input.keys.map(&:to_s) - allowed.flatten.map(&:to_s)
          raise Error::UnknownField.new(details: unknown) if unknown.any?
          input.deep_symbolize_keys
        end

        def find_post!
          identity = (params[:post_id] || params[:id]).to_s
          post = Post.find_by(id: identity) if identity.match?(/\A\d+\z/)
          post ||= Post.find_by(slug: identity)
          post || raise(Error::NotFound)
        end

        def render_result(result, status: nil)
          return render_error(result.error) unless result.success?
          status ||= result.post&.scheduled? ? :accepted : (result.created ? :created : :ok)
          render json: WriteResultSerializer.call(result, base_url: request.base_url), status: status
        end

        def render_error(error)
          prevent_caching!
          render json: ErrorSerializer.call(error), status: error.status
        end
      end
    end
  end
end
