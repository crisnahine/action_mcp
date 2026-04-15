# frozen_string_literal: true

require "test_helper"

class HostAuthorizationMiddlewareTest < ActiveSupport::TestCase
  # Test ActionDispatch::HostAuthorization behavior directly at the Rack level.
  # The middleware is built with a fixed host list at initialization time, so
  # runtime config mutations have no effect on an already-running stack.

  def make_app(hosts)
    inner = ->(_env) { [200, {}, ["ok"]] }
    ActionDispatch::HostAuthorization.new(inner, hosts)
  end

  def env_for(host)
    Rack::MockRequest.env_for("/", "HTTP_HOST" => host)
  end

  test "allows requests from whitelisted hosts" do
    app = make_app(["localhost", "127.0.0.1"])

    status, = app.call(env_for("localhost"))
    assert_equal 200, status

    status, = app.call(env_for("127.0.0.1"))
    assert_equal 200, status
  end

  test "rejects requests from non-whitelisted hosts with 403" do
    app = make_app(["localhost"])

    status, = app.call(env_for("evil.com"))
    assert_equal 403, status
  end

  test "allows all requests when host list is empty" do
    app = make_app([])

    status, = app.call(env_for("any-domain.com"))
    assert_equal 200, status
  end

  test "allows all requests when host list is nil" do
    app = make_app(nil)

    status, = app.call(env_for("any-domain.com"))
    assert_equal 200, status
  end

  test "handles subdomain pattern with dot prefix" do
    # ActionDispatch::HostAuthorization uses ".example.com" (leading dot) for subdomain wildcards
    app = make_app([".example.com"])

    status, = app.call(env_for("sub.example.com"))
    assert_equal 200, status

    status, = app.call(env_for("api.example.com"))
    assert_equal 200, status

    status, = app.call(env_for("evil.com"))
    assert_equal 403, status
  end

  test "host with port number matches base host entry" do
    app = make_app(["localhost"])

    status, = app.call(env_for("localhost:3000"))
    assert_equal 200, status
  end

  test "ipv6 host" do
    app = make_app(["[::1]"])

    status, = app.call(env_for("[::1]"))
    assert_equal 200, status
  end

  test "case-insensitive host matching" do
    app = make_app(["Example.COM"])

    status, = app.call(env_for("example.com"))
    assert_equal 200, status
  end

  test "engine standalone middleware stack includes HostAuthorization when app has hosts configured" do
    # Force the engine to build its standalone Rack app so config.middleware becomes
    # an actual ActionDispatch::MiddlewareStack we can inspect.
    _ = ActionMCP::Engine.app
    built = ActionMCP::Engine.config.middleware
    klasses = built.map(&:klass)

    if Rails.application.config.hosts.present?
      assert_includes klasses, ActionDispatch::HostAuthorization,
        "Expected HostAuthorization in engine middleware when config.hosts is set"
    else
      refute_includes klasses, ActionDispatch::HostAuthorization,
        "Expected no HostAuthorization in engine middleware when config.hosts is blank"
    end
  end
end
