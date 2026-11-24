require "test_helper"
require "action_dispatch/testing/integration"
require "nokogiri"
require "logger"
require "stringio"
require "cgi"

PanelOperator = Struct.new(:id)

class FakeTenancy
  Tenant = Struct.new(:code)

  def tenants = [Tenant.new("alfa"), Tenant.new("beta")]
  def find(identifier) = tenants.find { |tenant| tenant.code == identifier }
  def identifier(tenant) = tenant.code
  def label(tenant) = "Escola #{tenant.code}"
  def health(_tenant) = nil
  def shared_schema = "public"
  def schema_for(tenant) = tenant ? tenant.code : "public"
  def with(_tenant) = yield
end

class PanelTest < ActionDispatch::IntegrationTest
  MASKED = "•••••".freeze
  SECRETS = { cpf: "987.654.321-00", name: "Zeferino Distinto", email: "zef@secreto-exemplo.test", notes: "nota-privada-xyz",
              password_digest: "HASH-SENHA-123", api_token: "TOKEN-API-456", otp_secret: "OTP-789", encrypted_phone: "FONE-CIFRADO-000" }.freeze
  TABLE_SQL = /students|guardians|lucid_backoffice_|information_schema/

  def app = Rails.application

  def setup
    super
    Lucid::Backoffice.reset_configuration!
    Lucid::Backoffice::Current.reset
    drop_data
    create_data
    Lucid::Backoffice::Activity::Event.unscoped.delete_all
    Lucid::Backoffice::Reveal.delete_all
    @authenticate_calls = 0
  end

  def teardown
    drop_data
    Lucid::Backoffice::Current.reset
    Lucid::Backoffice.reset_configuration!
    super
  end

  def connection = ActiveRecord::Base.lease_connection

  def configure_panel(permissions: nil, tenancy: nil, &block)
    calls = -> { @authenticate_calls += 1 }
    Lucid::Backoffice.configure do |config|
      config.current_operator = ->(controller) { (id = controller.request.headers["X-Operator"]) && PanelOperator.new(id.to_i) }
      config.authenticate = lambda do |controller|
        calls.call
        controller.redirect_to("/login") unless controller.request.headers["X-Operator"]
      end
      config.authorize = ->(operator, permission, _context) { permissions.fetch(operator.id, []).include?(permission) } if permissions
      config.tenancy = tenancy if tenancy
      block&.call(config)
    end
  end

  def as(id) = { "X-Operator" => id.to_s }

  def create_data(schema = "public")
    connection.execute(<<~SQL)
      CREATE TABLE #{schema}.students (
        id bigserial PRIMARY KEY, guardian_id bigint, owner_type varchar, cpf varchar, name varchar, email varchar,
        status varchar, notes text, born_on date, score integer, active boolean,
        created_at timestamp, updated_at timestamp,
        password_digest varchar, api_token varchar, otp_secret varchar, encrypted_phone varchar
      )
    SQL
    connection.execute("CREATE TABLE #{schema}.guardians (id bigserial PRIMARY KEY, cpf varchar, name varchar, email varchar, status varchar)")
  end

  def drop_data
    %w[alfa beta].each { |schema| connection.execute("DROP SCHEMA IF EXISTS #{schema} CASCADE") }
    connection.execute("DROP TABLE IF EXISTS public.students")
    connection.execute("DROP TABLE IF EXISTS public.guardians")
  end

  def create_tenant_schemas
    %w[alfa beta].each do |schema|
      connection.execute("CREATE SCHEMA #{schema}")
      create_data(schema)
      insert_student(schema, **SECRETS.slice(:cpf, :name, :email, :notes))
    end
  end

  def insert_student(schema = "public", **values)
    row = { guardian_id: 42, owner_type: "Guardian", score: 7777, active: true, born_on: "2001-02-03",
            created_at: "2026-01-02 03:04:05", updated_at: "2026-01-02 03:04:05" }.merge(SECRETS).merge(values)
    columns = row.keys.map { |name| connection.quote_column_name(name) }.join(", ")
    quoted = row.values.map { |value| connection.quote(value) }.join(", ")
    connection.execute("INSERT INTO #{schema}.students (#{columns}) VALUES (#{quoted})")
  end

  def capture_sql
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end

  def write_yaml(content)
    path = File.join(Dir.mktmpdir, "classification.yml")
    File.write(path, content)
    path
  end

  def dom = Nokogiri::HTML(response.body)

  def csrf_token = dom.at_css("meta[name=csrf-token]")["content"]

  def with_forgery_protection
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  def events(name = nil)
    scope = Lucid::Backoffice::Activity::Event.order(:id)
    (name ? scope.where(name: name) : scope).to_a
  end

  def secret_values = SECRETS.values

  def refute_leaks(body)
    secret_values.each { |value| refute_includes body, value }
  end
end
