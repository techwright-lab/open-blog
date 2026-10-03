require_relative "test_helper"
require "minitest/mock"

class AuthenticationTest < ActiveSupport::TestCase
  setup { @hook = OpenBlog.config.authenticate; OpenBlog.config.authenticate = nil }
  teardown { OpenBlog.config.authenticate = @hook }

  test "only an exact single Bearer secret authenticates" do
    token, secret = OpenBlog::ApiToken.generate(name: "Publisher", scopes: [ "publish" ])
    actor = OpenBlog::Authentication.actor_for(request("Bearer #{secret}"))
    assert_equal "Publisher", actor.name
    assert_equal [ "publish" ], actor.scopes
    assert_equal "token:#{token.id}", actor.id
    [ nil, secret, "Token #{secret}", "Bearer #{secret},other", "Bearer #{secret} extra", "Bearer\n#{secret}" ].each do |header|
      assert_nil OpenBlog::Authentication.actor_for(request(header)), header.inspect
    end
  end

  test "host hook supersedes token lookup even when it rejects the request" do
    OpenBlog::ApiToken.stub(:authenticate, ->(*) { flunk "token fallback ran" }) do
      OpenBlog.config.authenticate = ->(_) { nil }
      assert_nil OpenBlog::Authentication.actor_for(request("Bearer unused"))
      OpenBlog.config.authenticate = ->(_) { Struct.new(:name).new("Host editor") }
      actor = OpenBlog::Authentication.actor_for(request(nil))
      assert_equal %w[read write publish], actor.scopes
      assert_equal "hook:Host editor", actor.id
      OpenBlog.config.authenticate = ->(_) { Struct.new(:name, :scopes, :id).new("Observer", [], 42) }
      actor = OpenBlog::Authentication.actor_for(request(nil))
      assert_equal [], actor.scopes
      assert_equal "hook:42", actor.id
    end
  end

  private

  def request(header)
    ActionDispatch::Request.new("HTTP_AUTHORIZATION" => header)
  end
end
