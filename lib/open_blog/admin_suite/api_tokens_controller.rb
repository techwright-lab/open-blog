module OpenBlog
  module AdminSuite
    class ApiTokensController < ::AdminSuite::ApplicationController
      include ::AdminSuite::Engine.routes.url_helpers

      GRACES = { "none" => nil, "3600" => 1.hour, "86400" => 24.hours }.freeze
      ERRORS = {
        invalid: "Check the name and choose at least one scope.",
        scope_not_allowed: "One of those scopes is not allowed for you.",
        expiry_invalid: "Choose an expiry the token policy allows.",
        grace_invalid: "Choose a grace period from the list.",
        not_rotatable: "Only an active token with an owner can be rotated.",
        already_rotated: "This token was already rotated.",
        tokens_inactive: "This host uses its own API authentication hook. Tokens issued here would not work.",
        unauthorized: "You cannot do that with this token."
      }.freeze

      protect_from_forgery with: :exception, prepend: true
      before_action :require_grant

      helper_method :grant, :tokens_inactive?, :grace_options, :no_expiry_allowed?, :token_time

      def index
        @tokens = ApiTokens.list(identity: @identity).tokens
      end

      def new
        return forbidden(ERRORS[:unauthorized]) unless grant.manage_own
        @scopes = grant.scopes.include?("read") ? %w[read] : []
        @expires_at = ApiTokens.default_expires_at.strftime("%Y-%m-%dT%H:%M")
      end

      def create
        @scopes = params[:scopes].is_a?(Array) ? params[:scopes].map(&:to_s) : []
        @expires_at = params[:expires_at].is_a?(String) ? params[:expires_at] : ""
        expires_at = parse_expiry(@expires_at)
        return render_new(:expiry_invalid) if expires_at == :invalid
        name = params[:name].is_a?(String) ? params[:name] : ""
        result = ApiTokens.issue(identity: @identity, name: name, scopes: @scopes, expires_at: expires_at)
        return reveal(result) if result.success?
        return forbidden(ERRORS[:unauthorized]) if result.error == :unauthorized
        render_new(result.error)
      end

      def show
        result = ApiTokens.find(identity: @identity, id: params[:id])
        return failed(result) unless result.success?
        @token = result.token
      end

      def revoke
        return unless confirmed?
        result = ApiTokens.revoke(identity: @identity, id: params[:id])
        return failed(result) unless result.success?
        redirect_to open_blog_api_token_path(result.token), notice: "Token revoked."
      end

      def rotate
        return unless confirmed?
        return render_show(ERRORS[:grace_invalid]) unless grace_options.value?(params[:grace].to_s)
        result = ApiTokens.rotate(identity: @identity, id: params[:id], grace: GRACES[params[:grace].to_s])
        return failed(result) unless result.success?
        @predecessor = result.token.predecessor
        reveal(result)
      end

      private

      def grant
        @grant
      end

      def require_grant
        @identity = OpenBlog.config.api_tokens.identity&.call(self)
        return forbidden("No trusted identity is configured for API token management.") if @identity.nil?
        @grant = ApiTokens.permissions(identity: @identity)
        forbidden("No token-management grant for this identity.") unless @grant && (@grant.manage_own || @grant.manage_all)
      end

      def token_time(time)
        "#{time.in_time_zone.strftime('%Y-%m-%d %H:%M:%S')} (#{Time.zone.name})"
      end

      def tokens_inactive?
        OpenBlog.config.authenticate ? true : false
      end

      def no_expiry_allowed?
        settings = OpenBlog.config.api_tokens
        !settings.require_expiry && settings.max_lifetime.nil?
      end

      def grace_options
        max = OpenBlog.config.api_tokens.max_grace.to_f
        { "No grace (revoke now)" => "none", "1 hour" => "3600", "24 hours" => "86400" }
          .select { |_label, value| GRACES[value].nil? || GRACES[value].to_f <= max }
      end

      def parse_expiry(value)
        return if value.strip.empty?
        Time.zone.parse(value) || :invalid
      rescue ArgumentError
        :invalid
      end

      def confirmed?
        return true if params[:confirm] == "1"
        render_show("Tick the confirmation box to continue.")
        false
      end

      def reveal(result)
        no_store
        @token = result.token
        @secret = result.secret
        render :revealed, status: :ok
      end

      def render_new(error)
        @error = ERRORS.fetch(error, ERRORS[:invalid])
        render :new, status: :unprocessable_content
      end

      def render_show(message)
        @token ||= ApiTokens.find(identity: @identity, id: params[:id]).token
        return not_found unless @token
        @error = message
        render :show, status: :unprocessable_content
      end

      def failed(result)
        case result.error
        when :not_found then not_found
        when :unauthorized then forbidden(ERRORS[:unauthorized])
        else render_show(ERRORS.fetch(result.error, ERRORS[:invalid]))
        end
      end

      def forbidden(message)
        @message = message
        render :error, status: :forbidden
      end

      def not_found
        @message = "No such token."
        render :error, status: :not_found
      end
    end
  end
end
