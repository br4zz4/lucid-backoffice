require "action_controller"
require "lucid/backoffice"
require "active_support/testing/time_helpers"
require "minitest/autorun"
require "tmpdir"

DATABASE_URL = ENV.fetch("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/lucid_backoffice_test")

def ensure_test_database(url)
  uri = URI.parse(url)
  name = uri.path.delete_prefix("/")
  ActiveRecord::Base.establish_connection(url.sub(%r{/#{Regexp.escape(name)}\z}, "/postgres"))
  connection = ActiveRecord::Base.connection
  exists = connection.select_value("SELECT 1 FROM pg_database WHERE datname = #{connection.quote(name)}")
  connection.create_database(name) unless exists
ensure
  ActiveRecord::Base.remove_connection
end

ensure_test_database(DATABASE_URL)
ActiveRecord::Base.establish_connection(DATABASE_URL)

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :lucid_backoffice_activity_events, force: true do |t|
    t.string :name, null: false
    t.string :outcome, null: false, default: "ok"
    t.string :actor_type, null: false
    t.bigint :actor_id
    t.string :tenant_identifier
    t.jsonb :subjects, null: false, default: []
    t.jsonb :changed_fields, null: false, default: []
    t.jsonb :payload, null: false, default: {}
    t.text :reason
    t.string :request_id
    t.inet :ip_address
    t.string :user_agent
    t.datetime :occurred_at, null: false
    t.datetime :created_at, null: false
    t.bigint :impersonation_id
  end

  create_table :lucid_backoffice_impersonations, force: true do |t|
    t.string :operator_type, null: false
    t.bigint :operator_id, null: false
    t.string :tenant_identifier
    t.string :user_type, null: false
    t.bigint :user_id, null: false
    t.text :reason, null: false
    t.jsonb :metadata, null: false, default: {}
    t.datetime :started_at, null: false
    t.datetime :expires_at, null: false
    t.datetime :entered_at
    t.datetime :ended_at
    t.string :end_reason
    t.datetime :created_at, null: false
  end

  create_table :impersonation_operators, force: true do |t|
    t.string :name
  end

  create_table :lucid_backoffice_reveals, force: true do |t|
    t.string :operator_type, null: false
    t.bigint :operator_id, null: false
    t.string :tenant_identifier
    t.string :category, null: false
    t.text :reason, null: false
    t.datetime :expires_at, null: false
    t.datetime :revoked_at
    t.datetime :created_at, null: false
  end

  create_table :widgets, force: true do |t|
    t.string :label
    t.integer :quantity
    t.timestamps
  end
end

class Widget < ActiveRecord::Base
end

class ImpersonationOperator < ActiveRecord::Base
end

ImpersonatedUser = Struct.new(:id)

module ImpersonationSupport
  REASON = "investigar chamado 4321".freeze
  USER_ID = 7
  TENANT = "alfa".freeze

  def configure_impersonation(permissions: %i[impersonate], duration: 30 * 60)
    @signed_in = []
    @signed_out = []
    signed_in = @signed_in
    signed_out = @signed_out
    Lucid::Backoffice.configure do |config|
      config.current_operator = ->(_request) { :operator }
      config.authenticate = ->(_request) { true }
      config.authorize = ->(_operator, permission, _context) { permissions.include?(permission) }
      config.impersonation.find_user = ->(_tenant, id) { id.to_i == USER_ID ? ImpersonatedUser.new(USER_ID) : nil }
      config.impersonation.sign_in = ->(controller, user) { signed_in << user.id && controller.session[:signed_in_user] = user.id }
      config.impersonation.sign_out = ->(_controller) { signed_out << true }
      config.impersonation.entry_url = ->(tenant) { "http://#{tenant}.example.test" }
      config.impersonation.return_url = ->(_impersonation) { "http://admin.example.test/backoffice" }
      config.impersonation.tenant_for_request = ->(request) { request.host.split(".").first }
      config.impersonation.duration = duration
    end
  end

  def create_operator(name = "operador")
    ImpersonationOperator.create!(name: name)
  end

  def start_impersonation(operator, user_id: USER_ID, reason: REASON, tenant: TENANT, metadata: {})
    Lucid::Backoffice::Impersonation.start(operator: operator, user_id: user_id, reason: reason, tenant: tenant, metadata: metadata)
  end

  def token_from(url)
    Rack::Utils.parse_query(URI.parse(url).query).fetch("token")
  end

  def reset_impersonation_data
    Lucid::Backoffice::Current.reset
    Lucid::Backoffice::Activity::Event.unscoped.delete_all
    Lucid::Backoffice::Impersonation.delete_all
    ImpersonationOperator.delete_all
  end

  def impersonation_events(name)
    Lucid::Backoffice::Activity::Event.where(name: name).order(:id).to_a
  end
end

class BackofficeTest < Minitest::Test
  def setup
    Lucid::Backoffice.reset_configuration!
  end

  def teardown
    Lucid::Backoffice.reset_configuration!
  end

  def configure_minimal
    Lucid::Backoffice.configure do |config|
      config.current_operator = ->(_request) { :operator }
      config.authenticate = ->(_request) { true }
      yield config if block_given?
    end
  end

  def write_yaml(content)
    dir = Dir.mktmpdir
    path = File.join(dir, "classification.yml")
    File.write(path, content)
    path
  end
end

class ActivityTest < BackofficeTest
  def setup
    super
    Lucid::Backoffice::Current.reset
    Lucid::Backoffice::Activity::Event.unscoped.delete_all
    Widget.delete_all
  end

  def teardown
    Lucid::Backoffice::Current.reset
    super
  end

  def build_event(**attributes)
    Lucid::Backoffice::Activity::Event.new(
      { name: "widget.created", actor_type: "System", occurred_at: Time.current }.merge(attributes)
    )
  end

  def events
    Lucid::Backoffice::Activity::Event.order(:id).to_a
  end
end

class IntegrationTest < ActivityTest
  def setup
    super
    @observers_before = Lucid::Case.configuration.events.observers.dup if defined?(Lucid::Case)
  end

  def teardown
    if defined?(Lucid::Case)
      Lucid::Case.configuration.events.observers.replace(@observers_before)
      Lucid::Case.configuration.events.recording = :disabled
    end
    super
  end
end

require "dummy_app"
