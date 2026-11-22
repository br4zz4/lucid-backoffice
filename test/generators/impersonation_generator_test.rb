require "test_helper"
require "rails/generators/test_case"
require "generators/lucid/backoffice/impersonation/impersonation_generator"

class BackofficeImpersonationGeneratorTest < Rails::Generators::TestCase
  tests Lucid::Backoffice::Generators::ImpersonationGenerator
  destination File.expand_path("../../tmp/generators_impersonation", __dir__)

  ROUTES = "Rails.application.routes.draw do\nend\n".freeze
  SCHEMA = "bo_impersonation_generator_check".freeze
  FILE = "create_lucid_backoffice_impersonations.rb".freeze

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

  def migration_path
    Dir[File.join(destination_root, "db/migrate/*_#{FILE}")].first
  end

  test "creates the impersonations migration" do
    # arrange
    # act
    run_generator

    # assert
    assert_migration "db/migrate/#{FILE}", /class CreateLucidBackofficeImpersonations < ActiveRecord::Migration\[/
  end

  test "migration has no tenancy declaration when Lucid::Tenancy is not defined" do
    # arrange
    # act
    without_tenancy { run_generator }

    # assert
    assert_migration("db/migrate/#{FILE}") { |content| refute_match(/tenancy/, content) }
  end

  test "migration declares tenancy :shared when Lucid::Tenancy is defined" do
    # arrange
    # act
    with_tenancy { run_generator }

    # assert
    assert_migration("db/migrate/#{FILE}") do |content|
      assert_match(/^  tenancy :shared$/, content)
      assert_operator content.index("tenancy :shared"), :<, content.index("def change")
    end
  end

  test "adds the entry route to config/routes.rb" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/routes.rb", %r{get "lucid_backoffice/impersonation/enter", to: "lucid/backoffice/impersonations#enter"}
  end

  test "adds the exit route to config/routes.rb" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/routes.rb", %r{delete "lucid_backoffice/impersonation", to: "lucid/backoffice/impersonations#destroy"}
  end

  test "the routes sit inside the routes block" do
    # arrange
    # act
    run_generator

    # assert
    assert_file "config/routes.rb" do |content|
      assert_operator content.index("draw do"), :<, content.index("impersonations#enter")
      assert_operator content.index("impersonations#destroy"), :<, content.rindex("end")
    end
  end

  test "generated migration creates the impersonations table and the impersonation_id column" do
    # arrange
    without_tenancy { run_generator }
    connection = ActiveRecord::Base.connection
    original_path = connection.schema_search_path
    connection.execute("DROP SCHEMA IF EXISTS #{SCHEMA} CASCADE")
    connection.execute("CREATE SCHEMA #{SCHEMA}")
    klass_name = FILE.delete_suffix(".rb").camelize

    begin
      connection.schema_search_path = SCHEMA
      connection.create_table(:lucid_backoffice_activity_events) { |t| t.string :name }

      # act
      TOPLEVEL_BINDING.eval(File.read(migration_path))
      ActiveRecord::Migration.suppress_messages { Object.const_get(klass_name).new.migrate(:up) }

      # assert
      table = connection.columns("lucid_backoffice_impersonations").to_h { |column| [column.name, column] }
      assert_equal %w[created_at end_reason ended_at entered_at expires_at id metadata operator_id operator_type reason started_at
                      tenant_identifier user_id user_type], table.keys.sort
      refute table["reason"].null
      assert_equal :jsonb, table["metadata"].type
      events = connection.columns("lucid_backoffice_activity_events").to_h { |column| [column.name, column] }
      assert_equal :integer, events["impersonation_id"].type.to_sym.then { |type| type == :bigint ? :integer : type }
      assert_includes connection.indexes("lucid_backoffice_impersonations").map(&:columns), %w[operator_type operator_id]
      assert_includes connection.indexes("lucid_backoffice_impersonations").map(&:columns), %w[user_type user_id]
      assert_includes connection.indexes("lucid_backoffice_activity_events").map(&:columns), ["impersonation_id"]
    ensure
      connection.schema_search_path = original_path
      connection.execute("DROP SCHEMA IF EXISTS #{SCHEMA} CASCADE")
      Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
    end
  end
end
