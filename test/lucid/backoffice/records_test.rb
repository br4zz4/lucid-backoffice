require "data_helper"

class RecordsTest < DataTest
  Records = Lucid::Backoffice::Records

  def list(**options)
    Records.list(schema: "public", table: "students", **options)
  end

  def find(id, **options)
    Records.find(schema: "public", table: "students", id: id, **options)
  end

  def test_unknown_table_is_not_found
    # arrange
    configure_minimal

    # act
    error = assert_raises(Records::NotFound) { Records.list(schema: "public", table: "nope") }

    # assert
    assert_kind_of Lucid::Backoffice::Error, error
  end

  def test_malicious_and_internal_table_names_are_not_found_without_sql_using_the_name
    # arrange
    configure_minimal
    names = ["users;drop", "pg_shadow", "schema_migrations", "students; DROP TABLE students", "public.students\"", "../students"]

    # act
    statements = capture_sql do
      names.each { |name| assert_raises(Records::NotFound, name) { Records.list(schema: "public", table: name) } }
    end

    # assert
    assert_empty statements.grep(/users;drop|pg_shadow|schema_migrations|DROP TABLE|\.\.\//i)
    assert_empty statements.grep(/\ASELECT .* FROM "?public"?\."?(users|pg_shadow|schema_migrations)/i)
    assert_equal 1, connection.select_value("SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'students'").to_i
  end

  def test_find_in_a_table_outside_the_catalog_is_not_found
    # arrange
    configure_minimal

    # act
    statements = capture_sql { assert_raises(Records::NotFound) { Records.find(schema: "public", table: "pg_shadow", id: 1) } }

    # assert
    assert_empty statements.grep(/pg_shadow/)
  end

  def test_hidden_table_is_not_found
    # arrange
    configure_minimal { |config| config.hidden_tables = ["students"] }

    # act and assert
    assert_raises(Records::NotFound) { list }
  end

  def test_unclassified_columns_are_masked
    # arrange
    configure_minimal
    insert_student(born_on: "2020-01-02", score: 7, active: true, notes: "x" * 41, status: nil)

    # act
    row = list.rows.first

    # assert
    assert_equal "•••••", cell(row, "cpf").value
    assert_equal "•••••", cell(row, "name").value
    assert_equal "—", cell(row, "status").value
    assert_equal "••/••/••••", cell(row, "born_on").value
    assert_equal "•••", cell(row, "score").value
    assert_equal "•••", cell(row, "active").value
    assert_equal "[texto, 41 caracteres]", cell(row, "notes").value
    assert row.reject { |entry| entry.column.category == "public" }.all?(&:masked)
  end

  def test_public_columns_are_in_the_clear
    # arrange
    configure_minimal
    insert_student(guardian_id: 9, owner_type: "Guardian")

    # act
    row = list.rows.first

    # assert
    assert_equal 9, cell(row, "guardian_id").value
    assert_equal "Guardian", cell(row, "owner_type").value
    assert_kind_of Integer, cell(row, "id").value
    refute cell(row, "id").masked
    refute cell(row, "guardian_id").masked
  end

  def test_secret_columns_are_not_returned_even_revealed
    # arrange
    configure_minimal
    insert_student
    connection.execute("UPDATE public.students SET password_digest = 'abc', api_token = 'tok'")

    # act
    page = list(revealed: Lucid::Backoffice.configuration.categories)

    # assert
    assert_empty page.columns.map(&:name).grep(SECRET_PATTERN)
    assert_empty page.rows.first.map { |entry| entry.value.to_s }.grep(/\A(abc|tok)\z/)
  end

  def test_reveal_opens_only_the_chosen_category
    # arrange
    write_classification("students:\n  email: contact\n  cpf: documents\n")
    insert_student

    # act
    row = list(revealed: ["contact"]).rows.first

    # assert
    assert_equal "maria@example.com", cell(row, "email").value
    refute cell(row, "email").masked
    assert_equal "•••••", cell(row, "cpf").value
    assert cell(row, "cpf").masked
    assert_equal "•••••", cell(row, "name").value
  end

  def test_filter_by_id_applies
    # arrange
    configure_minimal
    3.times { insert_student }
    target = connection.select_value("SELECT id FROM public.students ORDER BY id OFFSET 1 LIMIT 1")

    # act
    page = list(filters: { "id" => target.to_s })

    # assert
    assert_equal [target], page.rows.map { |row| cell(row, "id").value }
    assert_equal 1, page.total
    assert_empty page.ignored_filters
  end

  def test_filter_by_foreign_key_applies
    # arrange
    configure_minimal
    insert_student(guardian_id: 1)
    insert_student(guardian_id: 2)
    insert_student(guardian_id: 2)

    # act
    page = list(filters: { guardian_id: 2 })

    # assert
    assert_equal 2, page.total
    assert_equal [2, 2], page.rows.map { |row| cell(row, "guardian_id").value }
  end

  def test_filter_by_masked_column_is_ignored
    # arrange
    configure_minimal
    insert_student(name: "Maria")
    insert_student(name: "Joao")

    # act
    statements = capture_sql { @page = list(filters: { "name" => "Maria", "cpf" => "111" }) }

    # assert
    assert_equal 2, @page.total
    assert_equal %w[name cpf], @page.ignored_filters
    assert_empty statements.grep_v(/information_schema/).grep(/WHERE/i)
  end

  def test_filter_with_a_non_integer_value_is_ignored
    # arrange
    configure_minimal
    insert_student

    # act
    statements = capture_sql { @page = list(filters: { "id" => "1 OR 1=1", "guardian_id" => "abc" }) }

    # assert
    assert_equal 1, @page.total
    assert_equal %w[id guardian_id], @page.ignored_filters
    assert_empty statements.grep_v(/information_schema/).grep(/OR 1=1|WHERE/i)
  end

  def test_filter_on_an_unknown_column_is_ignored
    # arrange
    configure_minimal
    insert_student

    # act
    page = list(filters: { "ghost_id" => "1", "password_digest" => "1" })

    # assert
    assert_equal 1, page.total
    assert_equal %w[ghost_id password_digest], page.ignored_filters
  end

  def test_paginates_sixty_rows_in_three_pages
    # arrange
    configure_minimal { |config| config.page_size = 25 }
    connection.execute("INSERT INTO public.students (name) SELECT 'n' || g FROM generate_series(1, 60) g")

    # act
    pages = (1..3).map { |number| list(page: number) }

    # assert
    assert_equal [25, 25, 10], pages.map { |page| page.rows.size }
    assert_equal [3, 3, 3], pages.map(&:pages)
    assert_equal [60, 60, 60], pages.map(&:total)
    ids = pages.flat_map { |page| page.rows.map { |row| cell(row, "id").value } }
    assert_equal ids.sort, ids
    assert_equal 60, ids.uniq.size
  end

  def test_page_below_one_is_the_first_page
    # arrange
    configure_minimal
    insert_student

    # act
    page = list(page: 0)

    # assert
    assert_equal 1, page.page
    assert_equal 1, page.rows.size
  end

  def test_empty_table_has_one_page
    # arrange
    configure_minimal

    # act
    page = list

    # assert
    assert_equal 1, page.pages
    assert_equal 0, page.total
    assert_empty page.rows
  end

  def test_list_issues_only_reads_and_never_mentions_secret_columns
    # arrange
    configure_minimal
    insert_student

    # act
    statements = capture_sql { list(filters: { "id" => "1" }, revealed: ["contact"]) }.reject { |sql| sql.match?(/information_schema/) }

    # assert
    refute_empty statements
    assert statements.all? { |sql| sql.match?(/\A\s*SELECT\b/i) }, statements.inspect
    assert_empty statements.grep(WRITE_PATTERN)
    assert_empty statements.grep(SECRET_PATTERN)
  end

  def test_list_never_orders_by_a_masked_column
    # arrange
    configure_minimal
    insert_student

    # act
    statements = capture_sql { list }

    # assert
    orders = statements.grep(/ORDER BY/).map { |sql| sql[/ORDER BY.*?(LIMIT|\z)/m] }
    assert_equal 1, orders.grep(/ORDER BY "id"/).size
    assert_empty orders.grep(/"(cpf|name|email|status|notes)"/)
  end

  def test_find_returns_masked_cells
    # arrange
    configure_minimal
    insert_student
    id = connection.select_value("SELECT id FROM public.students").to_i

    # act
    row = find(id)

    # assert
    assert_equal id, cell(row, "id").value
    assert_equal "•••••", cell(row, "cpf").value
    assert cell(row, "cpf").masked
    assert_empty row.map { |entry| entry.column.name }.grep(SECRET_PATTERN)
  end

  def test_find_reveals_only_the_chosen_category
    # arrange
    write_classification("students:\n  email: contact\n")
    insert_student
    id = connection.select_value("SELECT id FROM public.students").to_i

    # act
    row = find(id.to_s, revealed: ["contact"])

    # assert
    assert_equal "maria@example.com", cell(row, "email").value
    assert_equal "•••••", cell(row, "name").value
  end

  def test_find_with_a_missing_or_non_integer_id_is_not_found
    # arrange
    configure_minimal
    insert_student

    # act
    statements = capture_sql do
      [0, 999_999, "abc", "1 OR 1=1", "1; DROP TABLE students", nil, ""].each do |id|
        assert_raises(Records::NotFound, id.inspect) { find(id) }
      end
    end

    # assert
    assert_empty statements.grep(/OR 1=1|DROP TABLE/)
  end

  def test_find_is_read_only_and_never_orders_by_masked_columns
    # arrange
    configure_minimal
    insert_student
    id = connection.select_value("SELECT id FROM public.students").to_i

    # act
    statements = capture_sql { find(id) }.reject { |sql| sql.match?(/information_schema/) }

    # assert
    assert statements.all? { |sql| sql.match?(/\A\s*SELECT\b/i) }
    assert_empty statements.grep(WRITE_PATTERN)
    assert_empty statements.grep(SECRET_PATTERN)
    assert_empty statements.grep(/ORDER BY "(cpf|name|email)"/)
  end

  def test_find_in_a_table_without_id_is_not_found
    # arrange
    configure_minimal
    connection.execute("CREATE TABLE public.bo_no_id (label varchar)")

    # act
    error = assert_raises(Records::NotFound) { Records.find(schema: "public", table: "bo_no_id", id: 1) }
    connection.execute("DROP TABLE public.bo_no_id")

    # assert
    assert_kind_of Lucid::Backoffice::Error, error
  end

  def test_resource_shapes_the_visible_columns
    # arrange
    configure_minimal
    insert_student
    resource = Class.new(Lucid::Backoffice::Resource) do
      table :students
      columns :name, :id
    end

    # act
    page = list(resource: resource)

    # assert
    assert_equal %w[name id], page.columns.map(&:name)
    assert_equal 2, page.rows.first.size
  end
end
