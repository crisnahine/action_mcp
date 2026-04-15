# frozen_string_literal: true

require "test_helper"

# Tests for ActionDispatch::HostAuthorization behavior (Host header, DNS rebinding layer 1)
# and ActionMCP's Origin header validation (DNS rebinding layer 2, MCP spec requirement).
#
# ActionDispatch::HostAuthorization — validates the Host header.
# ActionMCP::ApplicationController#verify_origin — validates the Origin header.
# Both are needed; they protect against different parts of the attack surface.
class HostAuthorizationMiddlewareTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # ActionDispatch::HostAuthorization — rack-level tests
  # ---------------------------------------------------------------------------

  def make_host_auth_app(hosts)
    inner = ->(_env) { [200, {}, ["ok"]] }
    ActionDispatch::HostAuthorization.new(inner, hosts)
  end

  def env_for(host)
    Rack::MockRequest.env_for("/", "HTTP_HOST" => host)
  end

  test "allows requests from whitelisted hosts" do
    app = make_host_auth_app(["localhost", "127.0.0.1"])

    status, = app.call(env_for("localhost"))
    assert_equal 200, status

    status, = app.call(env_for("127.0.0.1"))
    assert_equal 200, status
  end

  test "rejects requests from non-whitelisted hosts with 403" do
    app = make_host_auth_app(["localhost"])

    status, = app.call(env_for("evil.com"))
    assert_equal 403, status
  end

  test "allows all requests when host list is empty" do
    app = make_host_auth_app([])

    status, = app.call(env_for("any-domain.com"))
    assert_equal 200, status
  end

  test "allows all requests when host list is nil" do
    app = make_host_auth_app(nil)

    status, = app.call(env_for("any-domain.com"))
    assert_equal 200, status
  end

  test "handles subdomain pattern with dot prefix" do
    # ActionDispatch::HostAuthorization uses ".example.com" (leading dot) for subdomain wildcards
    app = make_host_auth_app([".example.com"])

    status, = app.call(env_for("sub.example.com"))
    assert_equal 200, status

    status, = app.call(env_for("api.example.com"))
    assert_equal 200, status

    status, = app.call(env_for("evil.com"))
    assert_equal 403, status
  end

  test "host with port number matches base host entry" do
    app = make_host_auth_app(["localhost"])

    status, = app.call(env_for("localhost:3000"))
    assert_equal 200, status
  end

  test "ipv6 host" do
    app = make_host_auth_app(["[::1]"])

    status, = app.call(env_for("[::1]"))
    assert_equal 200, status
  end

  test "case-insensitive host matching" do
    app = make_host_auth_app(["Example.COM"])

    status, = app.call(env_for("example.com"))
    assert_equal 200, status
  end

  test "engine standalone stack excludes HostAuthorization when config.hosts is blank" do
    # In the test environment config.hosts is not set, so the engine should NOT add
    # HostAuthorization to its standalone stack (guard: `if app.config.hosts.present?`).
    _ = ActionMCP::Engine.app
    built = ActionMCP::Engine.config.middleware
    refute_includes built.map(&:klass), ActionDispatch::HostAuthorization,
      "HostAuthorization should not be inserted when config.hosts is blank"
  end
end

# ---------------------------------------------------------------------------
# Origin header validation — MCP spec DNS rebinding requirement
# Tests go through the full controller stack via ActionDispatch::IntegrationTest
# so verify_origin before_action is exercised end-to-end.
# ---------------------------------------------------------------------------
class OriginValidationTest < ActionDispatch::IntegrationTest
  setup do
    @original_allowed_origins = ActionMCP.configuration.allowed_origins
  end

  teardown do
    ActionMCP.configuration.allowed_origins = @original_allowed_origins
  end

  # A GET / returns 405 (ActionMCP doesn't support SSE), but if Origin is blocked
  # verify_origin fires first and returns 403 before the action runs.
  test "allows request with no Origin header (non-browser client)" do
    get "/", headers: { "HOST" => "www.example.com" }
    # 405 means verify_origin passed — the action itself returned method-not-allowed
    assert_response :method_not_allowed
  end

  test "allows request when Origin host matches server host" do
    get "/", headers: { "HOST" => "www.example.com", "Origin" => "http://www.example.com" }
    assert_response :method_not_allowed
  end

  test "allows request when Origin host matches server host regardless of scheme or port" do
    get "/", headers: { "HOST" => "www.example.com", "Origin" => "https://www.example.com:443" }
    assert_response :method_not_allowed
  end

  test "blocks request when Origin host does not match server host" do
    get "/", headers: { "HOST" => "www.example.com", "Origin" => "http://evil.com" }
    assert_response :forbidden

    body = response.parsed_body
    assert_equal "2.0", body["jsonrpc"]
    assert_nil body["id"]
    assert_equal(-32_600, body["error"]["code"])
  end

  test "blocks null Origin" do
    get "/", headers: { "HOST" => "www.example.com", "Origin" => "null" }
    assert_response :forbidden
  end

  test "blocks request with explicit allowed_origins list when Origin not on list" do
    ActionMCP.configuration.allowed_origins = ["trusted.example.com"]

    get "/", headers: { "HOST" => "www.example.com", "Origin" => "http://other.example.com" }
    assert_response :forbidden
  end

  test "allows request when Origin host is in explicit allowed_origins list" do
    ActionMCP.configuration.allowed_origins = ["trusted.example.com"]

    get "/", headers: { "HOST" => "www.example.com", "Origin" => "https://trusted.example.com" }
    assert_response :method_not_allowed
  end

  test "allowed_origins supports Regexp patterns" do
    ActionMCP.configuration.allowed_origins = [/\Atrusted\.example\.com\z/i]

    get "/", headers: { "HOST" => "www.example.com", "Origin" => "https://trusted.example.com" }
    assert_response :method_not_allowed

    get "/", headers: { "HOST" => "www.example.com", "Origin" => "https://evil.example.com" }
    assert_response :forbidden
  end

  test "canonical DNS rebinding: blocks evil.com origin targeting localhost" do
    # DNS rebinding attack: attacker page at evil.com rebinds its domain to 127.0.0.1,
    # then fetches http://evil.com:3000/ (which reaches the local server).
    # Browser sends Host: evil.com but Origin: http://evil.com.
    # With ActionDispatch::HostAuthorization, Host: evil.com is blocked.
    # With verify_origin, even if Host passes, Origin: evil.com != localhost → blocked.
    get "/", headers: { "HOST" => "localhost", "Origin" => "http://evil.com" }
    assert_response :forbidden
  end

  test "allows same-host origin on localhost" do
    get "/", headers: { "HOST" => "localhost", "Origin" => "http://localhost" }
    assert_response :method_not_allowed
  end

  test "allows same-host origin on localhost with port" do
    get "/", headers: { "HOST" => "localhost", "Origin" => "http://localhost:3000" }
    assert_response :method_not_allowed
  end

  test "IPv6: allows same-host origin" do
    get "/", headers: { "HOST" => "[::1]", "Origin" => "http://[::1]" }
    assert_response :method_not_allowed
  end

  test "IPv6: blocks different origin when server is on IPv6 loopback" do
    get "/", headers: { "HOST" => "[::1]", "Origin" => "http://evil.com" }
    assert_response :forbidden
  end

  test "IPv6 allowed_origins: entry without brackets matches bracketed uri.host" do
    ActionMCP.configuration.allowed_origins = ["::1"]

    get "/", headers: { "HOST" => "[::1]", "Origin" => "http://[::1]" }
    assert_response :method_not_allowed
  end

  test "403 response body is JSON-RPC with no id per MCP spec" do
    post "/", params: { jsonrpc: "2.0", id: "test-1", method: "initialize", params: {} }.to_json,
         headers: {
           "HOST" => "www.example.com",
           "Origin" => "http://evil.com",
           "Content-Type" => "application/json",
           "Accept" => "application/json"
         }

    assert_response :forbidden
    body = response.parsed_body
    assert_equal "2.0", body["jsonrpc"]
    assert_nil body["id"], "spec requires id to be absent (null) in origin rejection responses"
    assert body.dig("error", "code")
    assert body.dig("error", "message")
  end
end
