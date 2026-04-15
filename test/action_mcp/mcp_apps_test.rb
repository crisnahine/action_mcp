# frozen_string_literal: true

require "test_helper"

module ActionMCP
  class McpAppsTest < ActiveSupport::TestCase
    def setup
      @original_tool_items = ActionMCP::ToolsRegistry.items.dup
    end

    def teardown
      ActionMCP::ToolsRegistry.instance_variable_set(:@items, @original_tool_items)
    end

    def build_tool(&block)
      klass = Class.new(ActionMCP::Tool)
      klass.define_singleton_method(:name) { "RendersUiTempTool#{SecureRandom.hex(4)}" }
      klass.abstract!
      klass.tool_name "renders_ui_temp_#{SecureRandom.hex(4)}"
      klass.description "temp"
      klass.class_eval(&block) if block
      klass
    end

    test "renders_ui serializes resourceUri under _meta.ui" do
      klass = build_tool { renders_ui "ui://widgets/panel", visibility: %i[model app] }

      assert_equal(
        { ui: { resourceUri: "ui://widgets/panel", visibility: [ "model", "app" ] } },
        klass.to_h[:_meta]
      )
    end

    test "renders_ui rejects non-ui:// URI" do
      assert_raises(ArgumentError) { build_tool { renders_ui "http://widgets/panel" } }
      assert_raises(ArgumentError) { build_tool { renders_ui "" } }
    end

    class StubSession
      attr_reader :client_capabilities

      def initialize(capabilities)
        @client_capabilities = capabilities
      end
    end

    class CapabilityProbe < ActionMCP::Capability
    end

    test "client_supports_ui? is true when the extension key is present" do
      caps = { "extensions" => { "io.modelcontextprotocol/ui" => {} } }
      instance = CapabilityProbe.new.with_context(session: StubSession.new(caps))

      assert instance.client_supports_ui?
    end

    test "client_supports_ui? is false when the extension key is absent" do
      instance = CapabilityProbe.new.with_context(session: StubSession.new("tools" => {}))

      refute instance.client_supports_ui?
    end

    test "weather tool declares renders_ui pointing at the dashboard" do
      assert_equal "ui://weather/dashboard", WeatherTool.to_h.dig(:_meta, :ui, :resourceUri)
    end

    test "weather dashboard resolve returns HTML content with _meta" do
      instance = WeatherDashboardTemplate.new({})
      response = instance.call

      refute response.error?
      content = response.contents.first
      assert_equal ActionMCP::MIME_TYPE_APP_HTML, content.mime_type
      refute_empty content.text
      assert content._meta[:ui][:prefersBorder]
    end
  end
end
