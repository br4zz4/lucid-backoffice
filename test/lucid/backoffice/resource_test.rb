require "data_helper"

class ResourceTest < DataTest
  Resource = Lucid::Backoffice::Resource

  def build(&block)
    Class.new(Resource) do
      table :students
      class_eval(&block) if block
    end
  end

  def test_group_is_stored_as_a_symbol
    # arrange
    resource = build { group "customers" }

    # act
    group = resource.group

    # assert
    assert_equal :customers, resource.group
    assert_equal :customers, group
  end

  def test_table_is_a_string
    # arrange
    resource = Class.new(Resource) { table :students }

    # act
    table = resource.table

    # assert
    assert_equal "students", table
  end

  def test_columns_choose_subset_and_order
    # arrange
    configure_minimal
    resource = build { columns :name, :id }
    columns = Lucid::Backoffice::Catalog.columns("public", "students")

    # act
    visible = resource.visible_columns(columns)

    # assert
    assert_equal %w[name id], visible.map(&:name)
    assert_equal %w[name id], resource.columns
  end

  def test_columns_naming_unknown_or_secret_columns_are_dropped
    # arrange
    configure_minimal
    resource = build { columns :id, :ghost, :password_digest, :name }
    columns = Lucid::Backoffice::Catalog.columns("public", "students")

    # act
    visible = resource.visible_columns(columns)

    # assert
    assert_equal %w[id name], visible.map(&:name)
  end

  def test_without_columns_everything_is_visible
    # arrange
    configure_minimal
    resource = build
    columns = Lucid::Backoffice::Catalog.columns("public", "students")

    # act
    visible = resource.visible_columns(columns)

    # assert
    assert_equal columns, visible
  end

  def test_hide_removes_columns
    # arrange
    configure_minimal
    resource = build { hide :email, "notes" }
    columns = Lucid::Backoffice::Catalog.columns("public", "students")

    # act
    visible = resource.visible_columns(columns).map(&:name)

    # assert
    refute_includes visible, "email"
    refute_includes visible, "notes"
    assert_includes visible, "name"
    assert_equal %w[email notes], resource.hidden
  end

  def test_hide_wins_over_columns
    # arrange
    configure_minimal
    resource = build do
      columns :id, :email
      hide :email
    end
    columns = Lucid::Backoffice::Catalog.columns("public", "students")

    # act
    visible = resource.visible_columns(columns)

    # assert
    assert_equal %w[id], visible.map(&:name)
  end

  def test_column_declares_display_type
    # arrange
    resource = build { column :status, :badge }

    # act
    display = resource.display["status"]

    # assert
    assert_equal :badge, display[:type]
  end

  def test_search_on_a_hidden_column_conflicts_naming_it
    # arrange
    configure_minimal

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) do
      build do
        hide :cpf
        search :cpf
      end
    end

    # assert
    assert_match(/cpf/, error.message)
    assert_match(/hidden/, error.message)
  end

  def test_search_on_a_secret_named_column_conflicts_naming_it
    # arrange
    configure_minimal

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { build { search :password_digest } }

    # assert
    assert_match(/password_digest/, error.message)
  end

  def test_search_on_a_masked_column_is_accepted
    # arrange
    configure_minimal

    # act
    unclassified = build { search :cpf, :name }

    # assert
    assert_equal %w[cpf name], unclassified.searchable
  end

  def test_search_on_a_classified_masked_column_is_accepted
    # arrange
    write_classification("students:\n  email: contact\n")

    # act
    resource = build { search :id, :email }

    # assert
    assert_equal %w[id email], resource.searchable
  end

  def test_search_on_id_is_allowed
    # arrange
    configure_minimal

    # act
    resource = build { search :id }

    # assert
    assert_equal %w[id], resource.searchable
  end

  def test_search_on_a_column_classified_public_is_allowed
    # arrange
    write_classification("students:\n  status: public\n")

    # act
    resource = build { search :id, :status }

    # assert
    assert_equal %w[id status], resource.searchable
  end

  def test_searchable_is_empty_by_default
    # arrange
    resource = build

    # act
    searchable = resource.searchable

    # assert
    assert_empty searchable
  end

  def test_filter_collects_symbols
    # arrange
    resource = build do
      filter :status
      filter "kind"
    end

    # act
    filters = resource.filters

    # assert
    assert_equal %i[status kind], filters
  end

  def test_association_declares_the_link
    # arrange
    resource = build { association :guardian, table: :guardians, foreign_key: :guardian_id }

    # act
    association = resource.associations.first

    # assert
    assert_equal Resource::Association.new(name: :guardian, table: "guardians", foreign_key: "guardian_id"), association
  end

  def test_label_from_a_masked_column_is_masked
    # arrange
    write_classification("students:\n  email: contact\n")
    resource = build { label(from: :email) { |row| row["email"] } }
    row = { "id" => 1, "email" => "maria@example.com" }

    # act
    masked = resource.label_for(row)
    revealed = resource.label_for(row, revealed: ["contact"])
    other = resource.label_for(row, revealed: ["documents"])

    # assert
    assert_equal "•••••", masked
    assert_equal "maria@example.com", revealed
    assert_equal "•••••", other
  end

  def test_label_from_a_public_column_is_in_the_clear
    # arrange
    configure_minimal
    resource = build { label(from: :id) { |row| "Student ##{row['id']}" } }

    # act
    label = resource.label_for({ "id" => 5 })

    # assert
    assert_equal "Student #5", label
  end

  def test_label_without_from_is_unclassified_and_masked
    # arrange
    configure_minimal
    resource = build { label { |row| row["email"] } }

    # act
    label = resource.label_for({ "id" => 1, "email" => "maria@example.com" })

    # assert
    assert_equal "•••••", label
  end

  def test_label_without_from_opens_only_with_unclassified_revealed
    # arrange
    configure_minimal
    resource = build { label { |row| row["email"] } }

    # act
    label = resource.label_for({ "id" => 1, "email" => "maria@example.com" }, revealed: ["unclassified"])

    # assert
    assert_equal "maria@example.com", label
  end

  def test_label_without_a_declaration_is_the_id
    # arrange
    resource = build

    # act
    label = resource.label_for({ "id" => 7, "email" => "maria@example.com" })

    # assert
    assert_equal "7", label
  end

  def test_for_finds_the_resource_by_table
    # arrange
    resource = build

    # act
    found = Resource.for("students")
    symbol = Resource.for(:students)
    missing = Resource.for("guardians")

    # assert
    assert_same resource, found
    assert_same resource, symbol
    assert_nil missing
  end

  def test_reset_clears_the_registry
    # arrange
    build

    # act
    Resource.reset!

    # assert
    assert_nil Resource.for("students")
  end

  def test_declarations_do_not_leak_between_resources
    # arrange
    first = build do
      hide :email
      filter :status
    end

    # act
    second = Class.new(Resource) { table :guardians }

    # assert
    assert_equal %w[email], first.hidden
    assert_empty second.hidden
    assert_empty second.filters
  end

  def test_creatable_on_a_table_without_model_is_a_configuration_conflict
    # arrange
    resource = Class.new(Resource) { table :ghosts }

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { resource.creatable :name }

    # assert
    assert_includes error.message, "ghosts"
  end

  def test_destroyable_on_a_table_without_model_is_a_configuration_conflict
    # arrange
    resource = Class.new(Resource) { table :ghosts }

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { resource.destroyable }

    # assert
    assert_includes error.message, "ghosts"
  end
end
