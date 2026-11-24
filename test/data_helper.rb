require "test_helper"

class DataTest < BackofficeTest
  WRITE_PATTERN = /\A\s*(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE)\b/i
  SECRET_PATTERN = /password|token|secret|digest|otp|encrypted/i

  def setup
    super
    drop_data_tables
    create_data_tables
  end

  def teardown
    drop_data_tables
    super
  end

  def connection
    ActiveRecord::Base.lease_connection
  end

  def create_data_tables(schema = "public")
    connection.execute(<<~SQL)
      CREATE TABLE #{schema}.students (
        id bigserial PRIMARY KEY, guardian_id bigint, owner_type varchar, cpf varchar, name varchar, email varchar,
        status varchar, notes text, born_on date, score integer, active boolean,
        created_at timestamp, updated_at timestamp,
        password_digest varchar, api_token varchar, otp_secret varchar, encrypted_phone varchar
      )
    SQL
    connection.execute(<<~SQL)
      CREATE TABLE #{schema}.guardians (id bigserial PRIMARY KEY, cpf varchar, name varchar, email varchar, status varchar)
    SQL
  end

  def drop_data_tables
    connection.execute("DROP TABLE IF EXISTS public.students CASCADE")
    connection.execute("DROP TABLE IF EXISTS public.guardians CASCADE")
    connection.execute("DROP TABLE IF EXISTS public.classrooms CASCADE")
    connection.execute("DROP SCHEMA IF EXISTS bo_limit CASCADE")
  end

  def insert_student(schema = "public", **values)
    row = { cpf: "111.222.333-44", name: "Maria", email: "maria@example.com", status: "active" }.merge(values)
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

  def cell(row, name)
    row.find { |entry| entry.column.name == name }
  end

  def write_classification(content)
    path = write_yaml(content)
    configure_minimal { |config| config.classification_path = path }
  end
end
