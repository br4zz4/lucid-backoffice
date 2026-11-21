require "action_controller"
require "lucid/backoffice"
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
  end

  create_table :widgets, force: true do |t|
    t.string :label
    t.integer :quantity
    t.timestamps
  end
end

class Widget < ActiveRecord::Base
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
