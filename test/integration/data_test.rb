require "integration_helper"

class DataIntegrationTest < PanelTest
  def setup
    super
    configure_panel(permissions: { 1 => %i[browse view_dashboard view_activity reveal] })
  end

  def test_data_lists_catalog_tables_without_internal_ones
    # arrange
    names = nil

    # act
    get "/backoffice/data", headers: as(1)
    names = dom.css("ul.lb-list a").map(&:text)

    # assert
    assert_response :ok
    assert_includes names, "students"
    assert_includes names, "guardians"
    assert_empty names & %w[schema_migrations ar_internal_metadata lucid_backoffice_reveals lucid_backoffice_activity_events]
    assert_equal "/backoffice/data/students", dom.at_css("ul.lb-list a[href$=students]")["href"]
  end

  def test_table_shows_public_columns_in_clear_and_masks_the_rest
    # arrange
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)
    row = dom.css("tbody tr").first
    cells = dom.css("thead th").map { |th| th.children.first.text.strip }.zip(row.css("td").map { |td| td.text.strip }).to_h

    # assert
    assert_equal "42", cells["guardian_id"]
    assert_equal "Guardian", cells["owner_type"]
    assert_equal "1", cells["id"]
    assert_equal MASKED, cells["cpf"]
    assert_equal MASKED, cells["name"]
    assert_equal MASKED, cells["email"]
    assert_equal "•••", cells["score"]
    assert_equal "•••", cells["active"]
    assert_equal "••/••/••••", cells["born_on"]
    assert_includes dom.css("th small").map(&:text), "unclassified"
    refute_leaks response.body
  end

  def test_secret_columns_are_absent_from_list_and_detail
    # arrange
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)
    list = response.body
    get "/backoffice/data/students/1", headers: as(1)
    detail = response.body

    # assert
    %w[password_digest api_token otp_secret encrypted_phone].each do |column|
      refute_includes list, column
      refute_includes detail, column
    end
  end

  def test_classification_yaml_makes_declared_columns_public
    # arrange
    path = write_yaml("students:\n  status: public\n")
    configure_panel(permissions: { 1 => %i[browse] }) { |config| config.classification_path = path }
    insert_student(status: "ativo")

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_includes dom.css("tbody td").map { |td| td.text.strip }, "ativo"
    refute_includes dom.css("th small").map(&:text), "public"
  end

  def test_detail_shows_masked_cells
    # arrange
    insert_student

    # act
    get "/backoffice/data/students/1", headers: as(1)
    pairs = dom.css("dt").map { |dt| dt.children.first.text.strip }.zip(dom.css("dd").map { |dd| dd.text.strip }).to_h

    # assert
    assert_equal MASKED, pairs["email"]
    assert_equal "42", pairs["guardian_id"]
    refute_leaks response.body
  end

  def test_long_text_is_masked_by_length
    # arrange
    insert_student(notes: "a" * 55)

    # act
    get "/backoffice/data/students/1", headers: as(1)

    # assert
    assert_includes response.body, "[texto, 55 caracteres]"
    refute_includes response.body, "a" * 55
  end

  def test_unknown_internal_and_malicious_tables_are_404_without_sql_naming_them
    # arrange
    names = ["pg_shadow", "schema_migrations", "ar_internal_metadata", "lucid_backoffice_reveals", "users;drop", "students\" --", "../x", "nope"]

    # act
    results = names.map do |name|
      status = nil
      statements = capture_sql do
        get "/backoffice/data/#{CGI.escape(name)}", headers: as(1)
        status = response.status
      rescue ActionController::RoutingError
        status = 404
      end
      [status, statements.reject { |sql| sql.include?("lucid_backoffice_") }.grep(/#{Regexp.escape(name)}/)]
    end

    # assert
    results.each { |status, naming| assert_equal [404, []], [status, naming] }
  end

  def test_unknown_record_is_404
    # arrange
    insert_student

    # act
    statuses = %w[999 abc 1;drop].map do |id|
      get "/backoffice/data/students/#{id}", headers: as(1)
      response.status
    end

    # assert
    assert_equal [404] * 3, statuses
  end

  def test_filter_by_id_returns_only_that_row
    # arrange
    3.times { insert_student }

    # act
    get "/backoffice/data/students", params: { filter: { id: 2 } }, headers: as(1)

    # assert
    assert_equal ["2"], dom.css("tbody tr td:first-child").map { |td| td.text.strip }
  end

  def test_filter_by_foreign_key_returns_matching_rows
    # arrange
    insert_student(guardian_id: 7)
    insert_student(guardian_id: 8)
    insert_student(guardian_id: 7)

    # act
    get "/backoffice/data/students", params: { filter: { guardian_id: 7 } }, headers: as(1)

    # assert
    assert_equal %w[1 3], dom.css("tbody tr td:first-child").map { |td| td.text.strip }
  end

  def test_filter_by_masked_column_is_ignored_with_warning
    # arrange
    insert_student(email: "a@x.test")
    insert_student(email: "b@x.test")

    # act
    get "/backoffice/data/students", params: { filter: { email: "a@x.test", id: "oops" } }, headers: as(1)

    # assert
    assert_equal 2, dom.css("tbody tr").size
    assert_includes dom.at_css(".lb-flash-warn").text, "email"
    refute_includes response.body, "a@x.test"
  end

  def test_pagination_splits_rows_in_pages_of_page_size
    # arrange
    60.times { insert_student }

    # act
    get "/backoffice/data/students", headers: as(1)
    first = dom.css("tbody tr").size
    links = dom.css("nav.lb-pager a").map { |a| a["href"] }
    get "/backoffice/data/students", params: { page: 3 }, headers: as(1)
    last = dom.css("tbody tr").map { |tr| tr.at_css("td").text.strip }

    # assert
    assert_equal 25, first
    assert_equal ["/backoffice/data/students?page=2", "/backoffice/data/students?page=3"], links
    assert_equal (51..60).map(&:to_s), last
  end

  def test_page_size_comes_from_configuration
    # arrange
    configure_panel(permissions: { 1 => %i[browse] }) { |config| config.page_size = 10 }
    30.times { insert_student }

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_equal 10, dom.css("tbody tr").size
    assert_equal 2, dom.css("nav.lb-pager a").size
  end

  def test_id_cell_links_to_the_record
    # arrange
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_equal "/backoffice/data/students/1", dom.at_css("tbody td a")["href"]
    assert_equal "1", dom.at_css("tbody td a").text
  end

  def test_resource_columns_and_hide_shape_the_list
    # arrange
    Class.new(Lucid::Backoffice::Resource) do
      table :students
      columns :id, :email, :status, :owner_type
      hide :status
    end
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)
    headers = dom.css("thead th").map { |th| th.children.first.text.strip }

    # assert
    assert_equal %w[id email owner_type], headers
    refute_leaks response.body
  end

  def test_resource_hide_applies_to_detail
    # arrange
    Class.new(Lucid::Backoffice::Resource) do
      table :students
      hide :owner_type, :guardian_id
    end
    insert_student

    # act
    get "/backoffice/data/students/1", headers: as(1)

    # assert
    names = dom.css("dt").map { |dt| dt.children.first.text.strip }
    refute_includes names, "owner_type"
    refute_includes names, "guardian_id"
    assert_includes names, "id"
  end

  def test_masked_values_never_reach_any_html_screen
    # arrange
    insert_student
    paths = ["/backoffice", "/backoffice/data", "/backoffice/data/students", "/backoffice/data/students/1", "/backoffice/data/guardians",
             "/backoffice/activity", "/backoffice/data/students?filter[cpf]=#{SECRETS[:cpf]}", "/backoffice/data/students/nope"]

    # act
    bodies = paths.map do |path|
      get path, headers: as(1)
      response.body
    end

    # assert
    bodies.each { |body| refute_leaks body }
  end

  def test_masked_values_never_reach_logs
    # arrange
    insert_student
    io = StringIO.new
    logger = Logger.new(io)
    loggers = [ActionController::Base, ActiveRecord::Base, ActionView::Base]
    previous = loggers.map(&:logger)
    loggers.each { |klass| klass.logger = logger }

    # act
    begin
      ["/backoffice/data/students", "/backoffice/data/students/1", "/backoffice/data/students/777"].each { |path| get path, headers: as(1) }
    ensure
      loggers.zip(previous) { |klass, old| klass.logger = old }
    end

    # assert
    assert_includes io.string, "Processing by Lucid::Backoffice::RecordsController#index"
    refute_leaks io.string
  end

  def test_not_found_response_does_not_echo_values
    # arrange
    insert_student

    # act
    get "/backoffice/data/students/777", headers: as(1)

    # assert
    assert_response :not_found
    refute_leaks response.body
  end

  def test_tenant_navigation_reads_the_tenant_schema
    # arrange
    create_tenant_schemas
    configure_panel(permissions: { 1 => %i[browse view_tenant] }, tenancy: FakeTenancy.new)
    connection.execute("UPDATE beta.students SET guardian_id = 99")

    # act
    get "/backoffice/tenants/beta/data/students", headers: as(1)
    guardians = dom.css("tbody tr td").map { |td| td.text.strip }

    # assert
    assert_response :ok
    assert_includes guardians, "99"
    refute_leaks response.body
  end

  def test_unknown_tenant_is_404
    # arrange
    create_tenant_schemas
    configure_panel(permissions: { 1 => %i[browse view_tenant] }, tenancy: FakeTenancy.new)

    # act
    get "/backoffice/tenants/zzz/data/students", headers: as(1)

    # assert
    assert_response :not_found
  end
end
