require "data_helper"

class CatalogTest < DataTest
  Catalog = Lucid::Backoffice::Catalog

  def test_lists_the_tables_of_the_schema
    # arrange
    configure_minimal

    # act
    tables = Catalog.tables("public")

    # assert
    assert_includes tables, "students"
    assert_includes tables, "guardians"
    assert_includes tables, "widgets"
  end

  def test_hides_the_gems_own_tables
    # arrange
    configure_minimal

    # act
    tables = Catalog.tables("public")

    # assert
    assert_empty tables.grep(/\Alucid_backoffice_/)
  end

  def test_hides_internal_tables
    # arrange
    configure_minimal
    connection.execute("DROP SCHEMA IF EXISTS bo_catalog CASCADE")
    connection.execute("CREATE SCHEMA bo_catalog")
    connection.execute("CREATE TABLE bo_catalog.schema_migrations (version varchar)")
    connection.execute("CREATE TABLE bo_catalog.ar_internal_metadata (key varchar)")
    connection.execute("CREATE TABLE bo_catalog.lucid_backoffice_other (id serial)")
    connection.execute("CREATE TABLE bo_catalog.visible_things (id serial)")

    # act
    tables = Catalog.tables("bo_catalog")
    connection.execute("DROP SCHEMA bo_catalog CASCADE")

    # assert
    assert_equal ["visible_things"], tables
  end

  def test_hides_configured_hidden_tables
    # arrange
    configure_minimal { |config| config.hidden_tables = [:guardians, "widgets"] }

    # act
    tables = Catalog.tables("public")

    # assert
    assert_includes tables, "students"
    refute_includes tables, "guardians"
    refute_includes tables, "widgets"
  end

  def test_table_predicate_follows_the_catalog
    # arrange
    configure_minimal

    # act
    results = [Catalog.table?("public", "students"), Catalog.table?("public", :students), Catalog.table?("public", "pg_shadow"),
               Catalog.table?("public", "schema_migrations"), Catalog.table?("public", "users;drop")]

    # assert
    assert_equal [true, true, false, false, false], results
  end

  def test_secret_columns_never_appear
    # arrange
    configure_minimal

    # act
    names = Catalog.columns("public", "students").map(&:name)

    # assert
    assert_empty names.grep(SECRET_PATTERN)
    assert_includes names, "cpf"
  end

  def test_secret_columns_follow_the_configured_pattern
    # arrange
    configure_minimal { |config| config.secret_columns = /\Acpf\z/ }

    # act
    names = Catalog.columns("public", "students").map(&:name)

    # assert
    refute_includes names, "cpf"
    assert_includes names, "api_token"
  end

  def test_maps_postgres_types
    # arrange
    configure_minimal

    # act
    types = Catalog.columns("public", "students").to_h { |column| [column.name, column.type] }

    # assert
    assert_equal :integer, types["id"]
    assert_equal :string, types["cpf"]
    assert_equal :text, types["notes"]
    assert_equal :date, types["born_on"]
    assert_equal :integer, types["score"]
    assert_equal :boolean, types["active"]
    assert_equal :datetime, types["created_at"]
  end

  def test_unknown_postgres_type_falls_back_to_string
    # arrange
    configure_minimal
    connection.execute("ALTER TABLE public.guardians ADD COLUMN location point")

    # act
    type = Catalog.columns("public", "guardians").find { |column| column.name == "location" }.type

    # assert
    assert_equal :string, type
  end

  def test_unclassified_columns_get_the_unclassified_category
    # arrange
    configure_minimal

    # act
    categories = Catalog.columns("public", "students").to_h { |column| [column.name, column.category] }

    # assert
    assert_equal "unclassified", categories["cpf"]
    assert_equal "unclassified", categories["name"]
    assert_equal "unclassified", categories["status"]
  end

  def test_categories_come_from_the_classification
    # arrange
    write_classification("students:\n  cpf: documents\n  email: contact\n")

    # act
    categories = Catalog.columns("public", "students").to_h { |column| [column.name, column.category] }

    # assert
    assert_equal "documents", categories["cpf"]
    assert_equal "contact", categories["email"]
    assert_equal "unclassified", categories["name"]
  end

  def test_public_by_convention
    # arrange
    configure_minimal

    # act
    categories = Catalog.columns("public", "students").to_h { |column| [column.name, column.category] }

    # assert
    %w[id guardian_id owner_type created_at updated_at].each { |name| assert_equal "public", categories[name], name }
  end

  def test_columns_keep_the_table_order
    # arrange
    configure_minimal

    # act
    names = Catalog.columns("public", "guardians").map(&:name)

    # assert
    assert_equal %w[id cpf name email status], names
  end

  def test_columns_of_a_missing_table_are_empty
    # arrange
    configure_minimal

    # act
    columns = Catalog.columns("public", "pg_shadow")

    # assert
    assert_empty columns
  end
end
