require "test_helper"
require "rails/generators/test_case"
require "generators/lucid/backoffice/install/install_generator"

class BackofficeInstallGeneratorTest < Rails::Generators::TestCase
  tests Lucid::Backoffice::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  ROUTES = "Rails.application.routes.draw do\nend\n".freeze
  SCHEMA = "bo_generator_check".freeze
  EVENTS_FILE = "create_lucid_backoffice_activity_events.rb".freeze
  REVEALS_FILE = "create_lucid_backoffice_reveals.rb".freeze

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), ROUTES)
  end

  def without_tenancy
    original = Lucid.send(:remove_const, :Tenancy) if Lucid.const_defined?(:Tenancy, false)
    yield
  ensure
    Lucid.const_set(:Tenancy, original) if original
  end

  def with_tenancy
    defined_before = Lucid.const_defined?(:Tenancy, false)
    Lucid.const_set(:Tenancy, Module.new) unless defined_before
    yield
  ensure
    Lucid.send(:remove_const, :Tenancy) unless defined_before
  end

  def migration_path(file)
    Dir[File.join(destination_root, "db/migrate/*_#{file}")].first
  end

  test "creates the initializer configuring Lucid::Backoffice" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/initializers/lucid_backoffice.rb", /Lucid::Backoffice\.configure/
  end

  test "initializer denies everything by default" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/initializers/lucid_backoffice.rb" do |content|
      assert_match(/^\s*config\.authorize = ->\(_operator, _permission, _context\) \{ false \}$/, content)
      assert_match(/config\.classification_path = Rails\.root\.join\("config\/data_classification\.yml"\)/, content)
    end
  end

  test "initializer documents the theme options" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/initializers/lucid_backoffice.rb" do |content|
      assert_match(/config\.brand_color/, content)
      assert_match(/config\.theme = /, content)
      assert_match(/config\.extra_stylesheets/, content)
      assert_match(/config\.stylesheet = /, content)
    end
  end

  test "creates the data classification file fully commented" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/data_classification.yml" do |content|
      lines = content.lines.map(&:strip).reject(&:empty?)
      assert_operator lines.size, :>, 0
      assert(lines.all? { |line| line.start_with?("#") })
      assert_match(/users:/, content)
    end
  end

  test "creates the two migrations" do
    # arrange
    # act
    run_generator

    # assert
    assert_migration "db/migrate/#{EVENTS_FILE}", /class CreateLucidBackofficeActivityEvents < ActiveRecord::Migration\[/
    assert_migration "db/migrate/#{REVEALS_FILE}", /class CreateLucidBackofficeReveals < ActiveRecord::Migration\[/
  end

  test "migrations have no tenancy declaration when Lucid::Tenancy is not defined" do
    # arrange
    # act
    without_tenancy { run_generator }

    # assert
    assert_migration("db/migrate/#{EVENTS_FILE}") { |content| refute_match(/tenancy/, content) }
    assert_migration("db/migrate/#{REVEALS_FILE}") { |content| refute_match(/tenancy/, content) }
  end

  test "migrations declare tenancy :shared when Lucid::Tenancy is defined" do
    # arrange
    # act
    with_tenancy { run_generator }

    # assert
    assert_migration("db/migrate/#{EVENTS_FILE}") { |content| assert_match(/^  tenancy :shared$/, content) }
    assert_migration("db/migrate/#{REVEALS_FILE}") { |content| assert_match(/^  tenancy :shared$/, content) }
  end

  test "the tenancy declaration comes before the change method" do
    # arrange
    # act
    with_tenancy { run_generator }

    # assert
    assert_migration("db/migrate/#{REVEALS_FILE}") do |content|
      assert_operator content.index("tenancy :shared"), :<, content.index("def change")
    end
  end

  test "mounts the engine in config/routes.rb" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/routes.rb", %r{mount Lucid::Backoffice::Engine => "/backoffice"}
  end

  test "mounts the engine inside the routes block" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/routes.rb" do |content|
      assert_operator content.index("draw do"), :<, content.index("mount Lucid")
      assert_operator content.index("mount Lucid"), :<, content.rindex("end")
    end
  end

  test "generated migrations create the tables, columns and indexes" do
    # arrange
    without_tenancy { run_generator }
    connection = ActiveRecord::Base.connection
    original_path = connection.schema_search_path
    connection.execute("DROP SCHEMA IF EXISTS #{SCHEMA} CASCADE")
    connection.execute("CREATE SCHEMA #{SCHEMA}")
    classes = []

    begin
      connection.schema_search_path = SCHEMA

      # act
      [EVENTS_FILE, REVEALS_FILE].each do |file|
        TOPLEVEL_BINDING.eval(File.read(migration_path(file)))
        klass = Object.const_get(file.delete_suffix(".rb").camelize)
        classes << klass.name
        ActiveRecord::Migration.suppress_messages { klass.new.migrate(:up) }
      end

      # assert
      events = connection.columns("lucid_backoffice_activity_events").to_h { |column| [column.name, column] }
      reveals = connection.columns("lucid_backoffice_reveals").to_h { |column| [column.name, column] }
      assert_equal %w[actor_id actor_type changed_fields created_at id ip_address name occurred_at outcome payload reason request_id subjects
                      tenant_identifier user_agent], events.keys.sort
      assert_equal "ok", events["outcome"].default
      assert_equal :jsonb, events["subjects"].type
      assert_equal :inet, events["ip_address"].type
      assert_equal %w[category created_at expires_at id operator_id operator_type reason revoked_at tenant_identifier], reveals.keys.sort
      refute reveals["reason"].null
      assert_includes connection.indexes("lucid_backoffice_activity_events").map(&:columns),
                      %w[tenant_identifier occurred_at]
      assert_includes connection.indexes("lucid_backoffice_activity_events").map(&:columns), ["name"]
      assert_includes connection.indexes("lucid_backoffice_reveals").map(&:columns),
                      %w[operator_type operator_id tenant_identifier category]
      assert_includes connection.indexes("lucid_backoffice_reveals").map(&:columns), ["expires_at"]
    ensure
      connection.schema_search_path = original_path
      connection.execute("DROP SCHEMA IF EXISTS #{SCHEMA} CASCADE")
      classes.each { |name| Object.send(:remove_const, name) }
    end
  end
end
