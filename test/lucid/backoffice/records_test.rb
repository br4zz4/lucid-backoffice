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

  def ids(page) = page.rows.map { |row| cell(row, "id").value }

  def query(**options) = Records::Query.new(**options)

  def test_filter_by_a_public_text_column_returns_only_matching_rows
    # arrange
    write_classification("students:\n  status: public\n")
    insert_student(status: "teacher")
    insert_student(status: "director")
    insert_student(status: "teacher")

    # act
    page = list(query: query(filters: { "status" => "teacher" }))

    # assert
    assert_equal 2, page.total
    assert_equal %w[teacher teacher], page.rows.map { |row| cell(row, "status").value }
    assert_empty page.ignored_filters
  end

  def test_filter_by_a_masked_column_is_ignored_and_not_used_in_sql
    # arrange
    configure_minimal
    insert_student(email: "a@x.test")
    insert_student(email: "b@x.test")

    # act
    statements = capture_sql { @page = list(query: query(filters: { "email" => "a@x.test" })) }

    # assert
    assert_equal 2, @page.total
    assert_equal %w[email], @page.ignored_filters
    assert_empty statements.grep_v(/information_schema/).grep(/a@x\.test|WHERE/i)
  end

  def test_filter_by_a_revealed_column_applies
    # arrange
    write_classification("students:\n  email: contact\n")
    insert_student(email: "a@x.test")
    insert_student(email: "b@x.test")

    # act
    page = list(query: query(filters: { "email" => "a@x.test" }), revealed: ["contact"])

    # assert
    assert_equal 1, page.total
    assert_empty page.ignored_filters
  end

  def test_search_is_case_insensitive_over_revealed_columns
    # arrange
    write_classification("students:\n  name: contact\n  email: contact\n")
    insert_student(name: "Maria Silva", email: "x@x.test")
    insert_student(name: "Joao", email: "MARIA@x.test")
    insert_student(name: "Pedro", email: "p@x.test")

    # act
    page = list(query: query(search: "maria"), revealed: ["contact"])

    # assert
    assert_equal 2, page.total
    assert_equal [1, 2], ids(page)
  end

  def test_search_does_not_cover_masked_columns_that_were_not_revealed
    # arrange
    write_classification("students:\n  name: contact\n  email: documents\n")
    insert_student(name: "Maria", email: "zed@x.test")
    insert_student(name: "Joao", email: "maria@x.test")

    # act
    page = list(query: query(search: "maria"), revealed: ["contact"])
    nothing = list(query: query(search: "zed"), revealed: ["contact"])

    # assert
    assert_equal [1], ids(page)
    assert_equal 0, nothing.total
  end

  def test_search_without_any_usable_column_matches_nothing
    # arrange
    configure_minimal
    insert_student(name: "Maria")

    # act
    page = list(query: query(search: "maria"))

    # assert
    assert_equal 0, page.total
    assert_empty page.rows
  end

  def test_search_treats_like_wildcards_literally
    # arrange
    write_classification("students:\n  name: contact\n")
    insert_student(name: "100% real")
    insert_student(name: "1000 real")
    insert_student(name: "a_b")
    insert_student(name: "axb")

    # act
    percent = list(query: query(search: "100%"), revealed: ["contact"])
    underscore = list(query: query(search: "a_b"), revealed: ["contact"])

    # assert
    assert_equal [1], ids(percent)
    assert_equal [3], ids(underscore)
  end

  def test_search_with_a_resource_covers_only_its_declared_columns
    # arrange
    write_classification("students:\n  name: contact\n  email: contact\n")
    insert_student(name: "Maria", email: "x@x.test")
    insert_student(name: "Joao", email: "maria@x.test")
    resource = Class.new(Lucid::Backoffice::Resource) do
      table :students
      search :email
    end

    # act
    page = list(query: query(search: "maria"), revealed: ["contact"], resource: resource)

    # assert
    assert_equal [2], ids(page)
  end

  def test_search_never_uses_hidden_columns
    # arrange
    configure_minimal
    insert_student
    connection.execute("UPDATE public.students SET password_digest = 'zzz', api_token = 'zzz'")

    # act
    page = list(query: query(search: "zzz"), revealed: Lucid::Backoffice.configuration.categories)

    # assert
    assert_equal 0, page.total
  end

  def test_search_and_filter_combine
    # arrange
    write_classification("students:\n  name: contact\n  status: public\n")
    insert_student(name: "Maria", status: "teacher")
    insert_student(name: "Maria", status: "director")

    # act
    page = list(query: query(search: "maria", filters: { "status" => "director" }), revealed: ["contact"])

    # assert
    assert_equal [2], ids(page)
  end

  def test_sort_by_a_visible_column_orders_ascending_and_descending
    # arrange
    write_classification("students:\n  status: public\n")
    insert_student(status: "b")
    insert_student(status: "c")
    insert_student(status: "a")

    # act
    asc = list(query: query(sort: "status", dir: "asc"))
    desc = list(query: query(sort: "status", dir: "desc"))

    # assert
    assert_equal [3, 1, 2], ids(asc)
    assert_equal [2, 1, 3], ids(desc)
    assert_empty asc.ignored_filters
  end

  def test_sort_by_a_revealed_column_applies
    # arrange
    write_classification("students:\n  name: contact\n")
    insert_student(name: "b")
    insert_student(name: "a")

    # act
    page = list(query: query(sort: "name"), revealed: ["contact"])

    # assert
    assert_equal [2, 1], ids(page)
  end

  def test_sort_by_a_masked_column_is_ignored_and_reported
    # arrange
    configure_minimal
    insert_student(name: "b")
    insert_student(name: "a")

    # act
    statements = capture_sql { @page = list(query: query(sort: "name", dir: "desc")) }

    # assert
    assert_equal [1, 2], ids(@page)
    assert_equal %w[name], @page.ignored_filters
    assert_empty statements.grep(/ORDER BY.*"name"/)
  end

  def test_sort_by_an_unknown_or_hidden_column_is_ignored
    # arrange
    configure_minimal
    insert_student

    # act
    unknown = list(query: query(sort: "ghost"))
    hidden = list(query: query(sort: "password_digest"))

    # assert
    assert_equal %w[ghost], unknown.ignored_filters
    assert_equal %w[password_digest], hidden.ignored_filters
  end

  def test_sort_direction_defaults_to_ascending_when_invalid
    # arrange
    write_classification("students:\n  status: public\n")
    insert_student(status: "b")
    insert_student(status: "a")

    # act
    page = list(query: query(sort: "status", dir: "sideways; DROP TABLE students"))

    # assert
    assert_equal [2, 1], ids(page)
  end

  def test_sort_breaks_ties_by_id
    # arrange
    write_classification("students:\n  status: public\n")
    3.times { insert_student(status: "same") }

    # act
    page = list(query: query(sort: "status", dir: "desc"))

    # assert
    assert_equal [1, 2, 3], ids(page)
  end

  def test_no_sql_names_a_hidden_or_unrevealed_masked_column_in_where_or_order_by
    # arrange
    write_classification("students:\n  status: public\n  email: contact\n")
    insert_student
    criteria = query(filters: { "password_digest" => "x", "api_token" => "x", "cpf" => "1", "email" => "m", "status" => "active" },
                     search: "maria", sort: "cpf")

    # act
    statements = capture_sql { list(query: criteria) }.reject { |sql| sql.match?(/information_schema/) }
    clauses = statements.flat_map { |sql| sql.scan(/\b(?:WHERE|ORDER BY)\b.*?(?=\bLIMIT\b|\z)/mi) }

    # assert
    refute_empty clauses
    assert_empty clauses.grep(SECRET_PATTERN)
    assert_empty clauses.grep(/"(cpf|name|email|notes)"/)
  end

  def test_no_sql_names_a_hidden_column_even_when_everything_is_revealed
    # arrange
    configure_minimal
    insert_student
    criteria = query(filters: { "password_digest" => "x", "otp_secret" => "x" }, search: "maria", sort: "encrypted_phone")

    # act
    statements = capture_sql { list(query: criteria, revealed: Lucid::Backoffice.configuration.categories) }
    clauses = statements.flat_map { |sql| sql.scan(/\b(?:WHERE|ORDER BY)\b.*?(?=\bLIMIT\b|\z)/mi) }

    # assert
    assert_empty clauses.grep(SECRET_PATTERN)
  end

  def test_filters_argument_and_query_filters_are_merged
    # arrange
    write_classification("students:\n  status: public\n")
    insert_student(guardian_id: 1, status: "a")
    insert_student(guardian_id: 2, status: "a")
    insert_student(guardian_id: 2, status: "b")

    # act
    page = list(filters: { "guardian_id" => "2" }, query: query(filters: { "status" => "a" }))

    # assert
    assert_equal [2], ids(page)
  end

  def test_foreign_key_cell_carries_a_link_to_the_target
    # arrange
    configure_minimal
    insert_student(guardian_id: 9)

    # act
    row = list.rows.first

    # assert
    assert_equal({ table: "guardians", id: 9 }, cell(row, "guardian_id").link)
    assert_nil cell(row, "id").link
    assert_nil cell(row, "owner_type").link
  end

  def test_foreign_key_link_is_also_present_on_the_record
    # arrange
    configure_minimal
    insert_student(guardian_id: 9)

    # act
    link = cell(find(1), "guardian_id").link

    # assert
    assert_equal({ table: "guardians", id: 9 }, link)
  end

  def test_null_foreign_key_has_no_link
    # arrange
    configure_minimal
    insert_student(guardian_id: nil)

    # act
    row = list.rows.first

    # assert
    assert_nil cell(row, "guardian_id").link
  end

  def test_masked_foreign_key_has_no_link
    # arrange
    configure_minimal
    write_classification("students:\n  mentor_ref: contact\n")
    connection.execute("ALTER TABLE public.students ADD COLUMN mentor_ref bigint")
    connection.execute("ALTER TABLE public.students ADD CONSTRAINT fk_mentor FOREIGN KEY (mentor_ref) REFERENCES public.guardians (id)")
    connection.execute("INSERT INTO public.guardians (id, name) VALUES (9, 'g')")
    insert_student(mentor_ref: 9)

    # act
    row = list.rows.first

    # assert
    assert cell(row, "mentor_ref").masked
    assert_nil cell(row, "mentor_ref").link
  end

  def test_revealed_foreign_key_has_a_link
    # arrange
    write_classification("students:\n  mentor_ref: contact\n")
    connection.execute("ALTER TABLE public.students ADD COLUMN mentor_ref bigint")
    connection.execute("ALTER TABLE public.students ADD CONSTRAINT fk_mentor FOREIGN KEY (mentor_ref) REFERENCES public.guardians (id)")
    connection.execute("INSERT INTO public.guardians (id, name) VALUES (9, 'g')")
    insert_student(mentor_ref: 9)

    # act
    row = list(revealed: ["contact"]).rows.first

    # assert
    assert_equal({ table: "guardians", id: 9 }, cell(row, "mentor_ref").link)
  end

  def test_related_counts_rows_pointing_at_the_record
    # arrange
    configure_minimal
    connection.execute("INSERT INTO public.guardians (id, name) VALUES (1, 'a'), (2, 'b')")
    connection.execute("ALTER TABLE public.students ADD CONSTRAINT fk_guardian FOREIGN KEY (guardian_id) REFERENCES public.guardians (id)")
    insert_student(guardian_id: 1)
    insert_student(guardian_id: 1)
    insert_student(guardian_id: 2)

    # act
    related = Records.related(schema: "public", table: "guardians", id: 1)

    # assert
    assert_equal [Records::Related.new(table: "students", column: "guardian_id", count: 2)], related
  end

  def test_related_omits_tables_with_zero_rows
    # arrange
    configure_minimal
    connection.execute("INSERT INTO public.guardians (id, name) VALUES (1, 'a'), (2, 'b')")
    connection.execute("ALTER TABLE public.students ADD CONSTRAINT fk_guardian FOREIGN KEY (guardian_id) REFERENCES public.guardians (id)")
    insert_student(guardian_id: 1)

    # act
    related = Records.related(schema: "public", table: "guardians", id: 2)

    # assert
    assert_empty related
  end

  def test_related_with_a_non_numeric_id_is_empty
    # arrange
    configure_minimal

    # act
    related = Records.related(schema: "public", table: "guardians", id: "1;drop")

    # assert
    assert_empty related
  end
end
