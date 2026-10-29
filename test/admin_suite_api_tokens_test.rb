require_relative "test_helper"

if Gem.loaded_specs.key?("admin_suite")
  require_relative "support/admin_suite"
  Rails.application.reload_routes_unless_loaded

  class AdminSuiteApiTokensTest < ActionDispatch::IntegrationTest
    Policy = Struct.new(:grants) do
      def grants_for(identity)
        grants[identity]
      end
    end

    ADA = "user:ada"
    BOB = "user:bob"
    AUDITOR = "user:auditor"
    INDEX = "/admin/open_blog/api_tokens"

    class << self
      attr_accessor :identity
    end

    with_routing do |set|
      set.draw do
        mount OpenBlog::Engine => "/blog"
        mount AdminSuite::Engine => "/admin"
      end
    end

    setup do
      @settings = OpenBlog.config.api_tokens
      @saved = %i[identity policy default_lifetime require_expiry max_lifetime max_grace].to_h { |key| [ key, @settings.public_send(key) ] }
      @saved_authenticate = OpenBlog.config.authenticate
      @saved_admin_authenticate = AdminSuite.config.authenticate
      @saved_forgery = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = false
      AdminSuite.config.authenticate = ->(_) { true }
      OpenBlog.config.authenticate = nil
      @settings.identity = ->(_controller) { AdminSuiteApiTokensTest.identity }
      @settings.policy = Policy.new({
        ADA => grant(own: true, scopes: %w[read write]),
        BOB => grant(own: true, scopes: %w[read write publish]),
        AUDITOR => grant(all: true, scopes: %w[read])
      })
      self.class.identity = ADA
    end

    teardown do
      @saved.each { |key, value| @settings.public_send(:"#{key}=", value) }
      OpenBlog.config.authenticate = @saved_authenticate
      AdminSuite.config.authenticate = @saved_admin_authenticate
      ActionController::Base.allow_forgery_protection = @saved_forgery
      self.class.identity = nil
    end

    def grant(own: false, all: false, scopes: [])
      OpenBlog::ApiTokens::Grant.new(manage_own: own, manage_all: all, scopes: scopes)
    end

    def issue_for(identity, name: "Deploy", scopes: %w[read], expires_at: 30.days.from_now)
      result = OpenBlog::ApiTokens.issue(identity: identity, name: name, scopes: scopes, expires_at: expires_at)
      assert result.success?, result.error.inspect
      result
    end

    def expiry_param(time = 30.days.from_now)
      time.strftime("%Y-%m-%dT%H:%M")
    end

    def shown(time)
      "#{time.in_time_zone.strftime('%Y-%m-%d %H:%M:%S')} (#{Time.zone.name})"
    end

    def document
      Nokogiri::HTML5(response.body)
    end

    def revealed_secret
      document.at_css("input#open-blog-api-token-secret[readonly]")&.[]("value")
    end

    test "a request without a trusted identity is forbidden and names the missing hook" do
      self.class.identity = nil
      get INDEX
      assert_response :forbidden
      assert_includes response.body, "No trusted identity is configured"
      @settings.identity = nil
      get "#{INDEX}/new"
      assert_response :forbidden
      assert_includes response.body, "No trusted identity is configured"
    end

    test "an identity without a grant is forbidden and told so" do
      self.class.identity = "user:stranger"
      get INDEX
      assert_response :forbidden
      assert_includes response.body, "No token-management grant for this identity"
      post INDEX, params: { name: "Nope", scopes: %w[read], expires_at: expiry_param }
      assert_response :forbidden
      assert_equal 0, OpenBlog::ApiToken.count
    end

    test "an own-only operator issues a token whose secret appears only in the create response" do
      get "#{INDEX}/new"
      assert_response :success
      form = document.at_css("form[action='#{INDEX}']")
      assert_equal "false", form["data-turbo"]
      assert_equal %w[read write], form.css("input[name='scopes[]']").map { |input| input["value"] }
      assert form.at_css("input[name='scopes[]'][value='read'][checked]")
      refute form.at_css("input[name='scopes[]'][value='write'][checked]")
      assert_includes response.body, "Without read"
      assert_equal "datetime-local", form.at_css("input[name='expires_at']")["type"]
      refute_empty form.at_css("input[name='expires_at']")["value"].to_s

      post INDEX, params: { name: "Deploy key", scopes: %w[read write], expires_at: expiry_param }
      assert_response :success
      assert_includes response.headers["Cache-Control"], "no-store"
      assert_nil response.headers["Location"]
      secret = revealed_secret
      assert_match(/\Aob_/, secret)
      assert_includes response.body, "Copy this token into your password manager now. It will not be shown again."
      assert document.at_css("button", text: "Copy")
      assert_empty flash.to_h
      refute_includes session.to_h.to_json, secret
      token = OpenBlog::ApiToken.authenticate(secret)
      assert_equal ADA, token.creator_identity
      assert_equal %w[read write], token.scopes

      get INDEX
      assert_response :success
      assert_includes response.body, "Deploy key"
      assert_includes response.body, token.token_prefix
      refute_includes response.body, secret
      get "#{INDEX}/#{token.id}"
      assert_response :success
      refute_includes response.body, secret
      assert_includes response.body, "issued"
      assert_includes response.body, ADA
    end

    test "validation failures re-render the form with 422" do
      post INDEX, params: { name: "", scopes: %w[read], expires_at: expiry_param }
      assert_response :unprocessable_content
      assert document.at_css("form[action='#{INDEX}']")
      post INDEX, params: { name: "Publisher", scopes: %w[publish], expires_at: expiry_param }
      assert_response :unprocessable_content
      assert_includes response.body, "not allowed"
      post INDEX, params: { name: { nested: "x" }, scopes: { "0" => "read" }, expires_at: expiry_param }
      assert_response :unprocessable_content
      post INDEX, params: { name: "Bad date", scopes: %w[read], expires_at: "soon-ish" }
      assert_response :unprocessable_content
      assert_includes response.body, "expiry"
      assert_equal 0, OpenBlog::ApiToken.count
      assert_nil response.headers["Location"]
    end

    test "blank expiry means no expiry only when policy allows it" do
      get "#{INDEX}/new"
      assert_includes response.body, "Leave blank for no expiry"
      post INDEX, params: { name: "Forever", scopes: %w[read], expires_at: "" }
      assert_response :success
      assert_nil OpenBlog::ApiToken.find_by(name: "Forever").expires_at

      @settings.require_expiry = true
      get "#{INDEX}/new"
      refute_includes response.body, "Leave blank for no expiry"
      post INDEX, params: { name: "Forever again", scopes: %w[read], expires_at: "" }
      assert_response :unprocessable_content
      assert_nil OpenBlog::ApiToken.find_by(name: "Forever again")
    end

    test "an own-only operator cannot see or change another creator's token" do
      other = issue_for(BOB, name: "Bob secret project").token
      get INDEX
      refute_includes response.body, "Bob secret project"
      get "#{INDEX}/#{other.id}"
      assert_response :not_found
      refute_includes response.body, "Bob secret project"
      post "#{INDEX}/#{other.id}/revoke", params: { confirm: "1" }
      assert_response :not_found
      post "#{INDEX}/#{other.id}/rotate", params: { confirm: "1", grace: "none" }
      assert_response :not_found
      assert_nil other.reload.revoked_at
      assert_nil other.successor_id
    end

    test "a manage-all operator revokes an ownerless token after confirming" do
      self.class.identity = AUDITOR
      token, = OpenBlog::ApiToken.generate(name: "Legacy CLI token")
      get INDEX
      assert_includes response.body, "Legacy CLI token"
      refute document.at_css("a[href='#{INDEX}/new']")
      get "#{INDEX}/new"
      assert_response :forbidden
      get "#{INDEX}/#{token.id}"
      assert_response :success
      refute document.at_css("form[action='#{INDEX}/#{token.id}/rotate']")
      document.css("form").each { |form| assert_equal "false", form["data-turbo"] }
      post "#{INDEX}/#{token.id}/revoke"
      assert_response :unprocessable_content
      assert_nil token.reload.revoked_at
      post "#{INDEX}/#{token.id}/revoke", params: { confirm: "1" }
      assert_redirected_to "#{INDEX}/#{token.id}"
      refute_nil token.reload.revoked_at
      assert_equal [ [ "revoked", AUDITOR ] ], token.events.pluck(:action, :actor_identity)
    end

    test "rotation reveals the replacement once and retires the old token" do
      old = issue_for(ADA).token
      get "#{INDEX}/#{old.id}"
      assert_equal [ "none", 1.hour.to_i.to_s, 24.hours.to_i.to_s ], document.css("select[name='grace'] option").map { |option| option["value"] }
      post "#{INDEX}/#{old.id}/rotate", params: { grace: "none" }
      assert_response :unprocessable_content
      assert_nil old.reload.successor_id

      post "#{INDEX}/#{old.id}/rotate", params: { grace: "none", confirm: "1" }
      assert_response :success
      assert_includes response.headers["Cache-Control"], "no-store"
      secret = revealed_secret
      replacement = OpenBlog::ApiToken.authenticate(secret)
      assert_equal replacement.id, old.reload.successor_id
      refute_nil old.revoked_at
      assert_includes response.body, "The previous token stopped working now."
      get "#{INDEX}/#{replacement.id}"
      refute_includes response.body, secret
    end

    test "rotation with grace keeps the old token until the cutoff and offers only allowed graces" do
      @settings.max_grace = 1.hour
      old = issue_for(ADA).token
      get "#{INDEX}/#{old.id}"
      assert_equal [ "none", 1.hour.to_i.to_s ], document.css("select[name='grace'] option").map { |option| option["value"] }
      post "#{INDEX}/#{old.id}/rotate", params: { grace: 24.hours.to_i.to_s, confirm: "1" }
      assert_response :unprocessable_content
      assert_nil old.reload.successor_id
      post "#{INDEX}/#{old.id}/rotate", params: { grace: 1.hour.to_i.to_s, confirm: "1" }
      assert_response :success
      old.reload
      assert_nil old.revoked_at
      assert_in_delta 1.hour.from_now, old.expires_at, 1.minute
      assert_includes response.body, "The previous token stops working at #{shown(old.expires_at)}."
      post "#{INDEX}/#{old.id}/rotate", params: { grace: "none", confirm: "1" }
      assert_response :unprocessable_content
    end

    test "rotation reports the old token's earlier expiry as the cutoff" do
      old = issue_for(ADA, expires_at: 30.minutes.from_now).token
      post "#{INDEX}/#{old.id}/rotate", params: { grace: 24.hours.to_i.to_s, confirm: "1" }
      assert_response :success
      assert_equal old.expires_at, old.reload.expires_at
      assert_includes response.body, "The previous token stops working at #{shown(old.expires_at)}."
      refute_includes response.body, "stopped working now"
    end

    test "expiry input and displayed times name the application time zone" do
      Time.use_zone("Tokyo") do
        token = issue_for(ADA).token
        get "#{INDEX}/new"
        assert_equal "Expires at (Tokyo)", document.at_css("label[for='expires_at']").text.strip
        get INDEX
        assert_includes response.body, shown(token.expires_at)
        get "#{INDEX}/#{token.id}"
        assert_includes response.body, shown(token.expires_at)
        assert_includes response.body, shown(token.created_at)
        post INDEX, params: { name: "Zoned", scopes: %w[read], expires_at: "2099-01-02T03:04" }
        assert_equal Time.zone.parse("2099-01-02T03:04"), OpenBlog::ApiToken.find_by(name: "Zoned").expires_at
        assert_includes response.body, "Expires: 2099-01-02 03:04:00 (Tokyo)."
      end
    end

    test "the reveal page renders under a locale without time formats" do
      saved = I18n.available_locales
      I18n.backend.store_translations(:zz, open_blog_test: "present")
      I18n.available_locales = saved + [ :zz ]
      I18n.with_locale(:zz) do
        assert_raises(I18n::MissingTranslationData) { I18n.l(Time.current, format: :long, raise: true) }
        post INDEX, params: { name: "Localized", scopes: %w[read], expires_at: expiry_param }
        assert_response :success
        assert_match(/\Aob_/, revealed_secret)
        get INDEX
        assert_response :success
        get "#{INDEX}/#{OpenBlog::ApiToken.find_by(name: 'Localized').id}"
        assert_response :success
      end
    ensure
      I18n.available_locales = saved
    end

    test "a host authentication hook shows the banner, hides New, and rejects issuance" do
      OpenBlog.config.authenticate = ->(_request) { nil }
      banner = "This host uses its own API authentication hook. Tokens issued here would not work."
      get INDEX
      assert_response :success
      assert_includes response.body, banner
      refute document.at_css("a[href='#{INDEX}/new']")
      get "#{INDEX}/new"
      assert_includes response.body, banner
      post INDEX, params: { name: "Useless", scopes: %w[read], expires_at: expiry_param }
      assert_response :unprocessable_content
      assert_nil revealed_secret
      assert_equal 0, OpenBlog::ApiToken.count
    end

    test "the index offers New when issuance works" do
      get INDEX
      assert document.at_css("a[href='#{INDEX}/new']")
    end

    test "navigation lists API tokens under Access" do
      get INDEX
      link = document.at_css("aside a[href='#{INDEX}']")
      assert link
      assert_includes link.text, "API tokens"
      assert_includes document.at_css("aside").text, "Access"
    end

    test "posts without a CSRF token are rejected" do
      ActionController::Base.allow_forgery_protection = true
      token = issue_for(ADA).token
      post INDEX, params: { name: "Forged", scopes: %w[read], expires_at: expiry_param }
      assert_response :unprocessable_content
      post "#{INDEX}/#{token.id}/revoke", params: { confirm: "1" }
      assert_response :unprocessable_content
      assert_equal 1, OpenBlog::ApiToken.count
      assert_nil token.reload.revoked_at
    end

    test "installing again or redrawing routes keeps one copy of each token route" do
      OpenBlog::AdminSuite.install!
      load AdminSuite::Engine.root.join("config/routes.rb").to_s
      names = AdminSuite::Engine.routes.routes.map(&:name)
      %w[open_blog_api_tokens new_open_blog_api_token open_blog_api_token revoke_open_blog_api_token rotate_open_blog_api_token].each do |name|
        assert_equal 1, names.count(name), name
      end
      assert_equal "open_blog/admin_suite/api_tokens", AdminSuite::Engine.routes.recognize_path("/open_blog/api_tokens")[:controller]
    end
  end
end
