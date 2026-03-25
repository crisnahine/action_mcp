# frozen_string_literal: true

class ConsolidatedMigration < ActiveRecord::Migration[8.1]
  def change
    create_table :action_mcp_sessions, id: :string do |t|
      t.string :role, null: false, default: "server", comment: "The role of the session"
      t.string :status, null: false, default: "pre_initialize"
      t.datetime :ended_at, comment: "The time the session ended"
      t.string :protocol_version
      t.json :server_capabilities, comment: "The capabilities of the server"
      t.json :client_capabilities, comment: "The capabilities of the client"
      t.json :server_info, comment: "The information about the server"
      t.json :client_info, comment: "The information about the client"
      t.boolean :initialized, null: false, default: false
      t.integer :messages_count, null: false, default: 0
      t.json :tool_registry, default: []
      t.json :prompt_registry, default: []
      t.json :resource_registry, default: []
      t.json :consents, default: {}, null: false
      t.json :session_data, default: {}, null: false
      t.timestamps
    end

    create_table :action_mcp_session_messages do |t|
      t.references :session, null: false,
                             foreign_key: { to_table: :action_mcp_sessions,
                                            on_delete: :cascade,
                                            on_update: :cascade,
                                            name: "fk_action_mcp_session_messages_session_id" },
                             type: :string
      t.string :direction, null: false, comment: "The message recipient", default: "client"
      t.string :message_type, null: false, comment: "The type of the message"
      t.string :jsonrpc_id
      t.json :message_json
      t.boolean :is_ping, default: false, null: false, comment: "Whether the message is a ping"
      t.boolean :request_acknowledged, default: false, null: false
      t.boolean :request_cancelled, null: false, default: false
      t.timestamps
    end

    create_table :action_mcp_session_subscriptions do |t|
      t.references :session, null: false,
                             foreign_key: { to_table: :action_mcp_sessions, on_delete: :cascade },
                             type: :string
      t.string :uri, null: false
      t.datetime :last_notification_at
      t.timestamps
    end

    create_table :action_mcp_session_tasks, id: :string do |t|
      t.references :session, null: false,
                             foreign_key: { to_table: :action_mcp_sessions,
                                            on_delete: :cascade,
                                            on_update: :cascade,
                                            name: "fk_action_mcp_session_tasks_session_id" },
                             type: :string
      t.string :status, null: false, default: "working"
      t.string :status_message
      t.string :request_method, comment: "e.g., tools/call, prompts/get"
      t.string :request_name, comment: "e.g., tool name, prompt name"
      t.json :request_params, comment: "Original request params"
      t.json :result_payload, comment: "Final result data"
      t.integer :ttl, comment: "Time to live in milliseconds"
      t.integer :poll_interval, comment: "Suggested polling interval in milliseconds"
      t.datetime :last_updated_at, null: false
      t.json :continuation_state, default: {}
      t.integer :progress_percent, comment: "Task progress as percentage 0-100"
      t.string :progress_message, comment: "Human-readable progress message"
      t.datetime :last_step_at
      t.timestamps

      t.index :status
      t.index %i[session_id status]
      t.index :created_at
    end
  end
end
