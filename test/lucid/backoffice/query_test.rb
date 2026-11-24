require "data_helper"

class QueryTest < DataTest
  Query = Lucid::Backoffice::Records::Query

  def columns
    Lucid::Backoffice::Catalog.columns("public", "students")
  end

  def test_defaults
    # arrange
    query = Query.new

    # act
    values = [query.filters, query.search, query.sort, query.dir]

    # assert
    assert_equal [{}, nil, nil, "asc"], values
  end

  def test_normalizes_inputs
    # arrange
    query = Query.new(filters: { status: "x" }, search: "  maria ", sort: :status, dir: "DESC")

    # act
    values = [query.filters, query.search, query.sort, query.dir]

    # assert
    assert_equal [{ "status" => "x" }, "maria", "status", "desc"], values
  end

  def test_blank_search_is_nil_and_invalid_direction_is_asc
    # arrange
    query = Query.new(search: "   ", dir: "up")

    # act
    values = [query.search, query.dir]

    # assert
    assert_equal [nil, "asc"], values
  end

  def test_usable_is_true_for_public_and_revealed_categories_only
    # arrange
    write_classification("students:\n  status: public\n  email: contact\n")
    status = columns.find { |column| column.name == "status" }
    email = columns.find { |column| column.name == "email" }

    # act
    results = [Query.usable?(status, []), Query.usable?(email, []), Query.usable?(email, ["contact"]), Query.usable?(email, ["documents"])]

    # assert
    assert_equal [true, false, true, false], results
  end

  def test_ignored_lists_unusable_filters_and_sort
    # arrange
    write_classification("students:\n  status: public\n")
    query = Query.new(filters: { "status" => "a", "email" => "b", "guardian_id" => "x", "ghost" => "1" }, sort: "email")

    # act
    ignored = query.ignored(columns, [])

    # assert
    assert_equal %w[email guardian_id ghost email], ignored
  end

  def test_sortable_requires_a_usable_column
    # arrange
    write_classification("students:\n  status: public\n  email: contact\n")

    # act
    results = [Query.new(sort: "status").sortable?(columns, []), Query.new(sort: "email").sortable?(columns, []),
               Query.new(sort: "email").sortable?(columns, ["contact"]), Query.new.sortable?(columns, [])]

    # assert
    assert_equal [true, false, true, false], results
  end

  def test_searchable_columns_default_to_usable_text_columns
    # arrange
    write_classification("students:\n  status: public\n  notes: public\n  email: contact\n  score: public\n")

    # act
    closed = Query.new.searchable_columns(columns, []).map(&:name)
    open = Query.new.searchable_columns(columns, ["contact"]).map(&:name)

    # assert
    assert_equal %w[owner_type status notes], closed.sort_by { |name| %w[owner_type status notes].index(name) }
    assert_equal %w[email owner_type status notes], open.sort_by { |name| %w[email owner_type status notes].index(name) }
  end

  def test_searchable_columns_follow_the_declared_list
    # arrange
    write_classification("students:\n  status: public\n  email: contact\n")

    # act
    names = Query.new.searchable_columns(columns, [], declared: %w[status email]).map(&:name)

    # assert
    assert_equal %w[status], names
  end
end
