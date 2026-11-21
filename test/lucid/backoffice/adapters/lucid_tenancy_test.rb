require "data_helper"
require "lucid/backoffice/adapters/lucid_tenancy"

class LucidTenancyAdapterTest < DataTest
  TEMPLATE = "bo_template".freeze
  ORGANIZATIONS = "bo_organizations".freeze
  DUMP = <<~RUBY.freeze
    ActiveRecord::Schema[7.2].define(version: 1) do
      create_table :students do |t|
        t.string :cpf
        t.string :name
        t.string :email
        t.string :status
      end

      create_table :guardians do |t|
        t.string :cpf
        t.string :name
        t.string :email
        t.string :status
      end
    end
  RUBY

  def setup
    super
    @schemas = []
    @dirs = []
    Lucid::Tenancy.reset_configuration!
    Lucid::Tenancy::State.tenant = nil
    connection.execute("DROP TABLE IF EXISTS public.#{ORGANIZATIONS}")
    connection.execute("CREATE TABLE public.#{ORGANIZATIONS} (id bigserial PRIMARY KEY, subdomain text UNIQUE, name text)")
    Object.send(:remove_const, :BoOrganization) if Object.const_defined?(:BoOrganization)
    organization = Class.new(ActiveRecord::Base)
    organization.table_name = ORGANIZATIONS
    Object.const_set(:BoOrganization, organization)
    organization.include(Lucid::Tenancy::Tenant)
    dir = Dir.mktmpdir("bo_tenancy")
    @dirs << dir
    path = File.join(dir, "tenant_schema.rb")
    File.write(path, DUMP)
    Lucid::Tenancy.configure do |config|
      config.tenant_model = "BoOrganization"
      config.template_schema = TEMPLATE
      config.tenant_schema_path = path
    end
    @schemas << TEMPLATE
    Lucid::Tenancy::Template.create!
    Lucid::Tenancy::Schema.with_path(TEMPLATE) { Lucid::Tenancy::Provisioner.load_dump(path) }
    configure_minimal { |config| config.tenancy = :lucid_tenancy }
    @adapter = Lucid::Backoffice::Tenancy.adapter
  end

  def teardown
    Lucid::Tenancy::State.tenant = nil
    connection.schema_search_path = '"public"'
    @schemas.each { |schema| connection.execute(%(DROP SCHEMA IF EXISTS "#{schema}" CASCADE)) }
    connection.execute("DROP TABLE IF EXISTS public.#{ORGANIZATIONS}")
    Object.send(:remove_const, :BoOrganization) if Object.const_defined?(:BoOrganization)
    @dirs.each { |dir| FileUtils.remove_entry(dir) if File.exist?(dir) }
    Lucid::Tenancy.reset_configuration!
    super
  end

  def provision(subdomain, name: subdomain.capitalize)
    tenant = BoOrganization.create!(subdomain: subdomain, name: name)
    @schemas << tenant.schema_name
    tenant.provision
    tenant
  end

  def test_adapter_is_the_lucid_tenancy_one
    # arrange and act
    adapter = @adapter

    # assert
    assert_instance_of Lucid::Backoffice::Adapters::LucidTenancy, adapter
    assert_same adapter, Lucid::Backoffice::Tenancy.adapter
    assert adapter.multi_tenant?
  end

  def test_tenants_are_sorted_by_identifier
    # arrange
    provision("beta")
    provision("alfa")

    # act
    identifiers = @adapter.tenants.map { |tenant| @adapter.identifier(tenant) }

    # assert
    assert_equal %w[alfa beta], identifiers
  end

  def test_tenants_are_empty_without_tenants
    # arrange and act
    tenants = @adapter.tenants

    # assert
    assert_empty tenants
  end

  def test_find_by_identifier
    # arrange
    provision("alfa")
    provision("beta")

    # act
    found = @adapter.find("beta")
    missing = @adapter.find("gama")

    # assert
    assert_equal "beta", @adapter.identifier(found)
    assert_nil missing
  end

  def test_label_uses_the_name_of_the_tenant
    # arrange
    tenant = provision("alfa", name: "Escola Alfa")

    # act
    label = @adapter.label(tenant)

    # assert
    assert_equal "Escola Alfa", label
  end

  def test_schema_for_a_tenant_and_for_nil
    # arrange
    alfa = provision("alfa")

    # act
    tenant_schema = @adapter.schema_for(alfa)
    shared_schema = @adapter.schema_for(nil)

    # assert
    assert_equal "alfa", tenant_schema
    assert_equal Lucid::Tenancy.configuration.shared_schema, shared_schema
    assert_equal shared_schema, @adapter.shared_schema
  end

  def test_records_list_reads_only_the_schema_of_the_tenant
    # arrange
    alfa = provision("alfa")
    beta = provision("beta")
    insert_student("alfa", name: "Aluno Alfa", cpf: "1")
    insert_student("beta", name: "Aluno Beta", cpf: "2")
    insert_student("beta", name: "Outro Beta", cpf: "3")
    revealed = Lucid::Backoffice.configuration.categories

    # act
    alfa_page = Lucid::Backoffice::Records.list(schema: @adapter.schema_for(alfa), table: "students", revealed: revealed)
    beta_page = Lucid::Backoffice::Records.list(schema: @adapter.schema_for(beta), table: "students", revealed: revealed)
    names = ->(page) { page.rows.map { |row| cell(row, "name").value } }

    # assert
    assert_equal ["Aluno Alfa"], names.call(alfa_page)
    assert_equal ["Aluno Beta", "Outro Beta"], names.call(beta_page)
  end

  def test_records_list_in_the_shared_schema_does_not_see_tenant_rows
    # arrange
    provision("alfa")
    insert_student("alfa", name: "Aluno Alfa")
    insert_student("public", name: "Shared")

    # act
    page = Lucid::Backoffice::Records.list(schema: @adapter.schema_for(nil), table: "students", revealed: ["unclassified"])

    # assert
    assert_equal ["Shared"], page.rows.map { |row| cell(row, "name").value }
  end

  def test_catalog_of_a_tenant_lists_its_tables
    # arrange
    alfa = provision("alfa")

    # act
    tables = Lucid::Backoffice::Catalog.tables(@adapter.schema_for(alfa))

    # assert
    assert_equal %w[guardians students], tables
  end

  def test_listing_a_tenant_table_does_not_change_the_search_path
    # arrange
    alfa = provision("alfa")
    before = connection.schema_search_path

    # act
    Lucid::Backoffice::Records.list(schema: @adapter.schema_for(alfa), table: "students")

    # assert
    assert_equal before, connection.schema_search_path
  end

  def test_health_of_a_tenant_in_sync_is_ok
    # arrange
    alfa = provision("alfa")

    # act
    health = @adapter.health(alfa)

    # assert
    assert_instance_of Lucid::Tenancy::Health, health
    assert health.ok?
    assert_equal "alfa", health.schema
  end

  def test_health_reports_a_tenant_that_drifted
    # arrange
    alfa = provision("alfa")
    connection.execute(%(DROP TABLE "alfa".guardians))

    # act
    health = @adapter.health(alfa)

    # assert
    refute health.ok?
    assert_equal ["guardians"], health.missing_tables
  end
end
