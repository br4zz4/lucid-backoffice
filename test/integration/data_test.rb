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

  def test_filter_by_a_public_text_column_in_the_url_returns_only_matching_rows
    # arrange
    path = write_yaml("students:\n  status: public\n")
    configure_panel(permissions: { 1 => %i[browse] }) { |config| config.classification_path = path }
    insert_student(status: "teacher")
    insert_student(status: "director")
    insert_student(status: "teacher")

    # act
    get "/backoffice/data/students?filter[status]=teacher", headers: as(1)

    # assert
    assert_equal %w[1 3], dom.css("tbody tr td:first-child").map { |td| td.text.strip }
    assert_empty dom.css(".lb-flash-warn")
  end

  def test_filter_by_a_masked_column_in_the_url_warns_and_does_not_filter
    # arrange
    insert_student(email: "a@x.test")
    insert_student(email: "b@x.test")

    # act
    get "/backoffice/data/students?filter[email]=a@x.test", headers: as(1)

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

  def shared_label = I18n.t("lucid_backoffice.shared")
  def crumbs = dom.css("header.lb-topbar .lb-crumbs a, header.lb-topbar .lb-crumbs b").map { |node| [node.name, node.text.strip, node["href"]] }
  def configure_tenant_data
    create_tenant_schemas
    configure_panel(permissions: { 1 => %i[browse view_tenant view_dashboard] }, tenancy: FakeTenancy.new)
  end

  def test_record_page_breadcrumb_runs_from_shared_to_the_record
    # arrange
    insert_student

    # act
    get "/backoffice/data/students/1", headers: as(1)

    # assert
    expected = [["a", shared_label, "/backoffice"], ["a", I18n.t("lucid_backoffice.data"), "/backoffice/data"],
                ["a", "students", "/backoffice/data/students"], ["b", "#1", nil]]
    assert_equal expected, crumbs
    assert dom.at_css("header.lb-topbar .lb-crumbs span.lb-crumb-sep")
  end

  def test_tenant_record_page_breadcrumb_includes_the_tenant
    # arrange
    configure_tenant_data

    # act
    get "/backoffice/tenants/alfa/data/students/1", headers: as(1)

    # assert
    expected = [["a", shared_label, "/backoffice"], ["a", "Escola alfa", "/backoffice/tenants/alfa"],
                ["a", I18n.t("lucid_backoffice.data"), "/backoffice/tenants/alfa/data"],
                ["a", "students", "/backoffice/tenants/alfa/data/students"], ["b", "#1", nil]]
    assert_equal expected, crumbs
  end

  def test_record_page_title_is_table_and_id
    # arrange
    insert_student

    # act
    get "/backoffice/data/students/1", headers: as(1)

    # assert
    assert_equal "students #1", dom.at_css(".lb-page-head h1").text.strip
  end

  def test_tenant_page_header_has_label_identifier_and_breadcrumb
    # arrange
    configure_tenant_data

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    head = dom.at_css(".lb-page-head h1")
    assert_includes head.text, "Escola alfa"
    assert_equal "alfa", head.at_css("small").text.strip
    assert_equal [["a", shared_label, "/backoffice"], ["b", "Escola alfa", nil]], crumbs
  end

  def test_page_without_crumbs_shows_only_the_context_in_the_topbar
    # arrange
    path = "/backoffice"

    # act
    get path, headers: as(1)

    # assert
    assert_includes dom.at_css("header.lb-topbar .lb-crumbs").text, shared_label
    assert_empty dom.css("header.lb-topbar .lb-crumbs .lb-crumb-sep")
  end

  def test_css_makes_primary_buttons_readable_and_styles_the_disabled_state_and_menu
    # arrange
    path = "/backoffice/assets/lucid_backoffice.css"

    # act
    get path
    css = response.body
    primary = css[/\.lb a\.lb-button\s*\{[^}]*\}/m]
    disabled = css[/\.lb-button\[aria-disabled="true"\][^{]*\{[^}]*\}/m]

    # assert
    assert primary, "missing .lb a.lb-button rule"
    assert_includes primary, "color: var(--lb-on-accent)"
    assert disabled, "missing disabled button rule"
    assert_includes disabled, "dashed"
    assert_includes css, ".lb-menu"
  end

  def label(key, **options) = I18n.t("lucid_backoffice.#{key}", **options, raise: true)

  def test_list_page_header_has_table_title_count_and_breadcrumb
    # arrange
    3.times { insert_student }

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_equal "students", dom.at_css(".lb-page-head h1").text.strip
    assert_equal label(:records_count, count: 3), dom.at_css(".lb-page-head .lb-page-sub").text.strip
    assert_equal [["a", shared_label, "/backoffice"], ["a", label(:data), "/backoffice/data"], ["b", "students", nil]], crumbs
  end

  def test_list_count_uses_the_singular_for_one_record
    # arrange
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_equal label(:records_count, count: 1), dom.at_css(".lb-page-sub").text.strip
  end

  def test_tenant_list_breadcrumb_includes_the_tenant
    # arrange
    configure_tenant_data

    # act
    get "/backoffice/tenants/alfa/data/students", headers: as(1)

    # assert
    expected = [["a", shared_label, "/backoffice"], ["a", "Escola alfa", "/backoffice/tenants/alfa"],
                ["a", label(:data), "/backoffice/tenants/alfa/data"], ["b", "students", nil]]
    assert_equal expected, crumbs
    assert_equal label(:records_count, count: 1), dom.at_css(".lb-page-sub").text.strip
  end

  def test_empty_table_shows_the_empty_state_instead_of_a_header_only_table
    # arrange
    path = "/backoffice/data/students"

    # act
    get path, headers: as(1)

    # assert
    assert_response :ok
    assert_empty dom.css("table.lb-table")
    assert_equal label(:no_records, table: "students"), dom.at_css(".lb-empty").text.strip
    assert_equal label(:records_count, count: 0), dom.at_css(".lb-page-sub").text.strip
  end

  def test_empty_tenant_table_shows_the_empty_state
    # arrange
    configure_tenant_data
    connection.execute("DELETE FROM alfa.students")

    # act
    get "/backoffice/tenants/alfa/data/students", headers: as(1)

    # assert
    assert_empty dom.css("table.lb-table")
    assert_equal label(:no_records, table: "students"), dom.at_css(".lb-empty").text.strip
  end

  def test_table_with_rows_keeps_the_table_and_no_empty_state
    # arrange
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_equal 1, dom.css("table.lb-table").size
    assert_empty dom.css(".lb-empty")
  end

  def test_tables_page_header_and_breadcrumb
    # arrange
    path = "/backoffice/data"

    # act
    get path, headers: as(1)

    # assert
    assert_equal label(:data), dom.at_css(".lb-page-head h1").text.strip
    assert_equal [["a", shared_label, "/backoffice"], ["b", label(:data), nil]], crumbs
    assert_includes dom.css("ul.lb-list a").map(&:text), "students"
  end

  def test_tenant_tables_page_breadcrumb
    # arrange
    configure_tenant_data

    # act
    get "/backoffice/tenants/alfa/data", headers: as(1)

    # assert
    assert_equal [["a", shared_label, "/backoffice"], ["a", "Escola alfa", "/backoffice/tenants/alfa"], ["b", label(:data), nil]], crumbs
    assert_equal label(:data), dom.at_css(".lb-page-head h1").text.strip
  end

  def test_pager_shows_the_visible_range_and_total
    # arrange
    configure_panel(permissions: { 1 => %i[browse] }) { |config| config.page_size = 10 }
    25.times { insert_student }

    # act
    get "/backoffice/data/students", headers: as(1)
    first = dom.at_css(".lb-pager-range").text.strip
    get "/backoffice/data/students", params: { page: 2 }, headers: as(1)
    second = dom.at_css(".lb-pager-range").text.strip
    get "/backoffice/data/students", params: { page: 3 }, headers: as(1)
    third = dom.at_css(".lb-pager-range").text.strip

    # assert
    assert_equal label(:pager_range, from: 1, to: 10, total: 25), first
    assert_equal label(:pager_range, from: 11, to: 20, total: 25), second
    assert_equal label(:pager_range, from: 21, to: 25, total: 25), third
    assert_equal 2, dom.css("nav.lb-pager a").size
  end

  def test_new_list_locale_keys_exist_in_both_languages
    # arrange
    keys = %w[records_count no_records enter pager_range]

    # act
    missing = %i[en pt-BR].flat_map { |locale| keys.reject { |key| I18n.exists?("lucid_backoffice.#{key}", locale) }.map { |key| "#{locale}.#{key}" } }

    # assert
    assert_empty missing
    assert_equal "1 registro", I18n.t("lucid_backoffice.records_count", count: 1, locale: :"pt-BR")
    assert_equal "5 registros", I18n.t("lucid_backoffice.records_count", count: 5, locale: :"pt-BR")
    assert_equal "1 record", I18n.t("lucid_backoffice.records_count", count: 1, locale: :en)
    assert_equal "5 records", I18n.t("lucid_backoffice.records_count", count: 5, locale: :en)
  end

  QUERY = "/backoffice/data/students/query".freeze
  LIST = "/backoffice/data/students".freeze

  def classify_and_reveal(reveal: true)
    path = write_yaml("students:\n  email: contact\n  name: contact\n  cpf: documents\n")
    configure_panel(permissions: { 1 => %i[browse reveal view_activity] }) { |config| config.classification_path = path }
    return unless reveal

    Lucid::Backoffice::Reveal.grant(operator: PanelOperator.new(1), category: "contact", reason: "investigar chamado 123")
  end

  def run_query(**params)
    post QUERY, params: params, headers: as(1)
    follow_redirect!(headers: as(1))
  end

  def names
    dom.css("tbody tr").map { |tr| tr.css("td")[dom.css("thead th").index { |th| th.text.strip.start_with?("name") }].text.strip }
  end

  def test_query_post_redirects_with_a_token_and_the_url_carries_no_search_text
    # arrange
    classify_and_reveal

    # act
    post QUERY, params: { criteria: { search: "Zeferino" } }, headers: as(1)

    # assert
    assert_response :redirect
    assert_match(%r{\A/backoffice/data/students\?q=[\w-]+\z}, URI(response.location).request_uri)
    refute_includes response.location, "Zeferino"
  end

  def test_revealed_column_is_searchable_through_the_token
    # arrange
    classify_and_reveal
    insert_student(name: "Zeferino Distinto")
    insert_student(name: "Outra Pessoa", email: "outra@x.test", cpf: "000")

    # act
    run_query(criteria: { search: "Zeferino" })

    # assert
    assert_response :ok
    assert_equal ["Zeferino Distinto"], names
    assert_empty dom.css(".lb-flash-warn")
  end

  def test_browse_event_records_the_column_names_and_not_the_search_text
    # arrange
    classify_and_reveal
    insert_student

    # act
    run_query(criteria: { search: "Zeferino" })
    stored = Lucid::Backoffice::Activity::Event.order(:id).map { |event| event.attributes.values.join(" ") }.join(" ")

    # assert
    payload = events("backoffice.browse").last.payload
    assert_includes payload["criteria"], "name"
    assert_includes payload["criteria"], "email"
    refute_includes stored, "Zeferino"
  end

  def test_search_is_ignored_with_a_warning_when_the_reveal_ends
    # arrange
    classify_and_reveal
    insert_student(name: "Zeferino Distinto")
    insert_student(name: "Outra Pessoa", email: "outra@x.test", cpf: "000")
    post QUERY, params: { criteria: { search: "Zeferino" } }, headers: as(1)
    token_url = response.location
    Lucid::Backoffice::Reveal.where(revoked_at: nil).update_all(revoked_at: Time.current)
    Lucid::Backoffice::Reveal.update_all(expires_at: 1.minute.ago)

    # act
    statements = capture_sql { get token_url, headers: as(1) }

    # assert
    assert_response :ok
    refute_includes response.body, "Zeferino Distinto"
    clauses = statements.grep(/Zeferino/).map { |sql| sql.split("WHERE", 2).last }
    refute_empty clauses
    clauses.each { |clause| refute_match(/"(name|email|cpf)"/, clause) }
  end

  def test_masked_column_is_not_offered_in_the_add_filter_select
    # arrange
    classify_and_reveal
    insert_student

    # act
    get LIST, headers: as(1)
    revealed_options = dom.css("select[name=filter_column] option").map(&:text)
    Lucid::Backoffice::Reveal.update_all(revoked_at: Time.current, expires_at: 1.minute.ago)
    get LIST, headers: as(1)
    masked_options = dom.css("select[name=filter_column] option").map(&:text)

    # assert
    assert_includes revealed_options, "email"
    assert_includes revealed_options, "name"
    refute_includes revealed_options, "cpf"
    assert_includes masked_options, "id"
    assert_includes masked_options, "guardian_id"
    assert_empty masked_options & %w[email name cpf]
  end

  def test_url_filter_on_a_masked_column_is_ignored_with_a_warning
    # arrange
    classify_and_reveal(reveal: false)
    insert_student(email: "alvo@x.test")
    insert_student(email: "outro@x.test")

    # act
    get LIST, params: { filter: { email: "alvo@x.test" } }, headers: as(1)

    # assert
    assert_response :ok
    assert_equal 2, dom.css("tbody tr").size
    assert_includes dom.at_css(".lb-flash-warn").text, "email"
  end

  def test_stored_filter_on_a_masked_column_is_ignored_with_a_warning
    # arrange
    classify_and_reveal
    insert_student(email: "alvo@x.test")
    insert_student(email: "outro@x.test")
    post QUERY, params: { criteria: { filters: { email: "alvo@x.test" } } }, headers: as(1)
    token_url = response.location
    Lucid::Backoffice::Reveal.update_all(revoked_at: Time.current, expires_at: 1.minute.ago)

    # act
    get token_url, headers: as(1)

    # assert
    assert_equal 2, dom.css("tbody tr").size
    assert_includes dom.at_css(".lb-flash-warn").text, "email"
    refute_includes response.body, "alvo@x.test"
  end

  def test_filter_chips_show_the_active_filters_and_each_has_a_remove_control
    # arrange
    classify_and_reveal
    insert_student(email: "alvo@x.test")
    insert_student(email: "outro@x.test")

    # act
    run_query(filter_column: "email", filter_value: "alvo@x.test")
    chips = dom.css(".lb-chip")
    rows = dom.css("tbody tr").size
    post QUERY, params: { criteria: { filters: {} } }, headers: as(1)
    follow_redirect!(headers: as(1))

    # assert
    assert_equal 1, chips.size
    assert_includes chips.first.text, "email"
    assert_includes chips.first.text, "alvo@x.test"
    assert_equal 1, chips.first.css("button").size
    assert_equal 1, rows
    assert_equal 2, dom.css("tbody tr").size
    assert_empty dom.css(".lb-chip")
  end

  def test_chip_remove_form_keeps_the_other_filters
    # arrange
    classify_and_reveal
    insert_student(email: "alvo@x.test")

    # act
    run_query(criteria: { filters: { email: "alvo@x.test", guardian_id: "42" } })
    forms = dom.css("form.lb-chip")
    removing_email = forms.find { |form| form.text.include?("email") }
    kept = removing_email.css("input[type=hidden]").map { |input| [input["name"], input["value"]] }.to_h

    # assert
    assert_equal 2, forms.size
    assert_equal "42", kept["criteria[filters][guardian_id]"]
    refute kept.key?("criteria[filters][email]")
  end

  def test_public_column_header_sorts_through_a_get_link_and_click_inverts
    # arrange
    classify_and_reveal
    insert_student(guardian_id: 5)
    insert_student(guardian_id: 9)

    # act
    get LIST, headers: as(1)
    asc_href = dom.css("thead th a").find { |a| a.text.include?("guardian_id") }["href"]
    get asc_href, headers: as(1)
    ascending = dom.css("tbody tr td:nth-child(2)").map { |td| td.text.strip }
    desc_href = dom.css("thead th a").find { |a| a.text.include?("guardian_id") }["href"]
    get desc_href, headers: as(1)
    descending = dom.css("tbody tr td:nth-child(2)").map { |td| td.text.strip }

    # assert
    assert_includes asc_href, "sort=guardian_id"
    assert_includes asc_href, "dir=asc"
    assert_includes desc_href, "dir=desc"
    assert_equal %w[5 9], ascending
    assert_equal %w[9 5], descending
  end

  def test_masked_column_header_has_no_sort_control
    # arrange
    classify_and_reveal(reveal: false)
    insert_student

    # act
    get LIST, headers: as(1)
    header = dom.css("thead th").find { |th| th.text.include?("cpf") }

    # assert
    assert_empty header.css("a")
    assert_empty header.css("button")
  end

  def test_revealed_column_header_sorts_through_a_post_button
    # arrange
    classify_and_reveal
    insert_student(name: "Bruno")
    insert_student(name: "Ana", email: "a@x.test")

    # act
    get LIST, headers: as(1)
    button = dom.css("thead th button").find { |b| b.text.include?("name") }
    first_value = button["value"]
    run_query(sort_toggle: first_value)
    ascending = names
    button = dom.css("thead th button").find { |b| b.text.include?("name") }
    run_query(sort_toggle: button["value"])
    descending = names

    # assert
    assert_equal "name:asc", first_value
    assert_equal %w[Ana Bruno], ascending
    assert_equal %w[Bruno Ana], descending
  end

  def test_url_sort_on_a_masked_column_is_ignored_with_a_warning
    # arrange
    classify_and_reveal(reveal: false)
    insert_student

    # act
    get LIST, params: { sort: "cpf", dir: "desc" }, headers: as(1)

    # assert
    assert_response :ok
    assert_includes dom.at_css(".lb-flash-warn").text, "cpf"
  end

  def test_token_from_another_table_is_ignored
    # arrange
    classify_and_reveal
    insert_student(name: "Zeferino Distinto")
    insert_student(name: "Outra Pessoa", email: "outra@x.test", cpf: "000")
    post QUERY, params: { criteria: { search: "Zeferino" } }, headers: as(1)
    token = Rack::Utils.parse_query(URI(response.location).query)["q"]

    # act
    get "/backoffice/data/guardians", params: { q: token }, headers: as(1)

    # assert
    assert_response :ok
    assert_empty dom.css(".lb-flash-warn")
    refute_includes dom.at_css("input[type=search]")["value"].to_s, "Zeferino"
  end

  def test_token_from_another_tenant_is_ignored
    # arrange
    create_tenant_schemas
    path = write_yaml("students:\n  name: contact\n")
    configure_panel(permissions: { 1 => %i[browse reveal view_tenant] }, tenancy: FakeTenancy.new) { |config| config.classification_path = path }
    Lucid::Backoffice::Reveal.grant(operator: PanelOperator.new(1), category: "contact", reason: "investigar chamado 123", tenant: "alfa")
    Lucid::Backoffice::Reveal.grant(operator: PanelOperator.new(1), category: "contact", reason: "investigar chamado 123", tenant: "beta")
    post "/backoffice/tenants/alfa/data/students/query", params: { criteria: { search: "Zeferino" } }, headers: as(1)
    token = Rack::Utils.parse_query(URI(response.location).query)["q"]

    # act
    get "/backoffice/tenants/beta/data/students", params: { q: token }, headers: as(1)
    foreign = dom.at_css("input[type=search]")["value"].to_s
    get "/backoffice/tenants/alfa/data/students", params: { q: token }, headers: as(1)
    own = dom.at_css("input[type=search]")["value"].to_s

    # assert
    assert_equal "", foreign
    assert_equal "Zeferino", own
  end

  def test_unknown_token_is_ignored
    # arrange
    classify_and_reveal
    insert_student

    # act
    get LIST, params: { q: "inexistente" }, headers: as(1)

    # assert
    assert_response :ok
    assert_equal 1, dom.css("tbody tr").size
  end

  def test_only_the_last_twenty_queries_are_kept
    # arrange
    classify_and_reveal
    insert_student(name: "Zeferino Distinto")
    tokens = []

    # act
    22.times do |index|
      post QUERY, params: { criteria: { search: index.zero? ? "Zeferino" : "x#{index}" } }, headers: as(1)
      tokens << Rack::Utils.parse_query(URI(response.location).query)["q"]
    end
    get LIST, params: { q: tokens.first }, headers: as(1)
    oldest = dom.at_css("input[type=search]")["value"].to_s
    get LIST, params: { q: tokens.last }, headers: as(1)
    newest = dom.at_css("input[type=search]")["value"].to_s

    # assert
    assert_equal "", oldest
    assert_equal "x21", newest
  end

  def test_query_in_a_tenant_redirects_to_the_tenant_list
    # arrange
    create_tenant_schemas
    configure_panel(permissions: { 1 => %i[browse view_tenant] }, tenancy: FakeTenancy.new)

    # act
    post "/backoffice/tenants/alfa/data/students/query", params: { criteria: { search: "x" } }, headers: as(1)

    # assert
    assert_match(%r{\A/backoffice/tenants/alfa/data/students\?q=[\w-]+\z}, URI(response.location).request_uri)
  end

  def link_fixture(schema = "public")
    connection.execute("INSERT INTO #{schema}.guardians (id, name) VALUES (42, 'g42'), (43, 'g43')")
    connection.execute(
      "ALTER TABLE #{schema}.students ADD CONSTRAINT fk_guardian FOREIGN KEY (guardian_id) REFERENCES #{schema}.guardians (id)"
    )
  end

  def test_foreign_key_value_links_to_the_record
    # arrange
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)
    list_link = dom.at_css("tbody a[href$='/guardians/42']")
    get "/backoffice/data/students/1", headers: as(1)
    detail_link = dom.at_css("dd a[href$='/guardians/42']")

    # assert
    assert_equal "/backoffice/data/guardians/42", list_link["href"]
    assert_equal "42", list_link.text.strip
    assert_equal "/backoffice/data/guardians/42", detail_link["href"]
  end

  def test_foreign_key_link_stays_in_the_tenant
    # arrange
    configure_tenant_data

    # act
    get "/backoffice/tenants/alfa/data/students/1", headers: as(1)

    # assert
    assert_equal "/backoffice/tenants/alfa/data/guardians/42", dom.at_css("dd a[title=guardians]")["href"]
  end

  def test_null_foreign_key_is_not_a_link
    # arrange
    insert_student(guardian_id: nil)

    # act
    get "/backoffice/data/students/1", headers: as(1)

    # assert
    assert_empty dom.css("dd a[title=guardians]")
  end

  def test_related_card_lists_tables_with_counts_and_filtered_links
    # arrange
    link_fixture
    insert_student(guardian_id: 42)
    insert_student(guardian_id: 42)
    insert_student(guardian_id: 43)

    # act
    get "/backoffice/data/guardians/42", headers: as(1)
    item = dom.at_css("section.lb-related li")

    # assert
    assert_equal I18n.t("lucid_backoffice.related"), dom.at_css("section.lb-related h2").text
    assert_equal "students 2", item.text.squish
    assert_equal "/backoffice/data/students?filter%5Bguardian_id%5D=42", item.at_css("a")["href"]
  end

  def test_following_the_related_link_lists_only_the_matching_rows
    # arrange
    link_fixture
    insert_student(guardian_id: 42)
    insert_student(guardian_id: 43)
    insert_student(guardian_id: 42)
    get "/backoffice/data/guardians/42", headers: as(1)
    href = dom.at_css("section.lb-related li a")["href"]

    # act
    get href, headers: as(1)

    # assert
    assert_equal %w[1 3], dom.css("tbody tr td:first-child").map { |td| td.text.strip }
    assert_empty dom.css(".lb-flash-warn")
  end

  def test_related_card_is_absent_without_references
    # arrange
    link_fixture
    insert_student(guardian_id: 42)
    connection.execute("INSERT INTO public.guardians (id, name) VALUES (50, 'lonely')")

    # act
    get "/backoffice/data/guardians/50", headers: as(1)

    # assert
    assert_response :ok
    assert_empty dom.css("section.lb-related")
  end

  def test_tenant_related_card_links_inside_the_tenant_and_counts_its_schema
    # arrange
    configure_tenant_data
    link_fixture("alfa")
    insert_student("alfa", guardian_id: 42)
    insert_student("beta", guardian_id: 42)

    # act
    get "/backoffice/tenants/alfa/data/guardians/42", headers: as(1)
    item = dom.at_css("section.lb-related li")

    # assert
    assert_equal "students 2", item.text.squish
    assert_equal "/backoffice/tenants/alfa/data/students?filter%5Bguardian_id%5D=42", item.at_css("a")["href"]
  end

  def capture_controller_log
    io = StringIO.new
    logger = Logger.new(io)
    loggers = [ActionController::Base, ActiveRecord::Base, ActionView::Base]
    previous = loggers.map(&:logger)
    loggers.each { |klass| klass.logger = logger }
    yield
    io.string
  ensure
    loggers.zip(previous) { |klass, old| klass.logger = old }
  end

  def test_posted_search_and_filter_values_are_filtered_in_the_log
    # arrange
    classify_and_reveal
    insert_student(email: "alvo@x.test")

    # act
    log = capture_controller_log do
      post QUERY, params: { criteria: { search: "BUSCA-SIGILOSA-77", filters: { email: "FILTRO-SIGILOSO-88" } } }, headers: as(1)
      post QUERY, params: { filter_column: "email", filter_value: "COLUNA-SIGILOSA-99" }, headers: as(1)
    end

    # assert
    assert_includes log, "Processing by Lucid::Backoffice::RecordsController#query"
    assert_includes log, "[FILTERED]"
    %w[BUSCA-SIGILOSA-77 FILTRO-SIGILOSO-88 COLUNA-SIGILOSA-99].each { |term| refute_includes log, term }
  end

  def test_get_filter_values_are_filtered_in_the_log
    # arrange
    classify_and_reveal
    insert_student

    # act
    log = capture_controller_log { get LIST, params: { filter: { status: "GET-SIGILOSO-55" } }, headers: as(1) }

    # assert
    assert_includes log, "[FILTERED]"
    refute_includes log, "GET-SIGILOSO-55"
  end

  def test_long_stored_criteria_are_truncated_and_never_overflow_the_session
    # arrange
    classify_and_reveal
    insert_student
    long = "x" * 5000
    tokens = []

    # act
    30.times do |index|
      post QUERY, params: { criteria: { search: long + index.to_s, filters: { status: long, email: long, name: long, cpf: long, id: long } } },
                  headers: as(1)
      tokens << response.location
    end
    stored = session[:lb_queries]

    # assert
    assert_response :redirect
    assert_operator stored.to_json.bytesize, :<=, 1500
    stored.each_value do |entry|
      assert_operator entry["search"].length, :<=, 100
      assert_operator entry["filters"].size, :<=, 4
      entry["filters"].each { |name, value| assert_operator name.length + value.length, :<=, 200 }
    end
    assert_includes stored.keys, tokens.last.split("q=").last
    get tokens.last, headers: as(1)
    assert_response :ok
  end

  def test_browse_event_only_records_applicable_criteria
    # arrange
    classify_and_reveal(reveal: false)
    insert_student

    # act
    get LIST, params: { filter: { email: "alvo@x.test", ghost: "1", password_digest: "x", id: "1" }, sort: "email" }, headers: as(1)

    # assert
    criteria = events("backoffice.browse").last.payload["criteria"]
    assert_includes criteria, "id"
    %w[email ghost password_digest].each { |name| refute_includes criteria, name }
  end

  def test_related_card_hides_tables_the_operator_cannot_browse
    # arrange
    link_fixture
    insert_student(guardian_id: 42)
    configure_panel do |config|
      config.authorize = ->(_operator, permission, context) { permission == :browse && context[:table] != "students" }
    end

    # act
    get "/backoffice/data/guardians/42", headers: as(1)

    # assert
    assert_response :ok
    assert_empty dom.css("section.lb-related")
  end

  def test_search_without_usable_columns_warns_and_is_listed_as_ignored
    # arrange
    classify_and_reveal
    Class.new(Lucid::Backoffice::Resource) do
      table :students
      search :name
    end
    insert_student(name: "Zeferino Distinto")
    post QUERY, params: { criteria: { search: "Zeferino" } }, headers: as(1)
    token_url = response.location
    Lucid::Backoffice::Reveal.update_all(revoked_at: Time.current, expires_at: 1.minute.ago)

    # act
    get token_url, headers: as(1)

    # assert
    assert_response :ok
    assert_includes dom.at_css(".lb-flash-warn").text, "search"
  end

  def test_filter_popover_has_visible_labels_tied_to_the_select_and_the_input
    # arrange
    classify_and_reveal
    insert_student

    # act
    get LIST, headers: as(1)
    menu = dom.at_css("details.lb-menu")
    column_label = menu.at_css("label[for=lb-filter-column]")
    value_label = menu.at_css("label[for=lb-filter-value]")

    # assert
    assert column_label
    assert value_label
    assert_equal label(:filter_column), column_label.text.strip
    assert_equal label(:filter_value), value_label.text.strip
    assert_equal "select", menu.at_css("#lb-filter-column").name
    assert_equal "input", menu.at_css("#lb-filter-value").name
    assert_nil menu.at_css("#lb-filter-column")["aria-label"]
    assert_nil menu.at_css("#lb-filter-value")["aria-label"]
  end

  def test_filter_popover_submit_says_apply_filter
    # arrange
    classify_and_reveal
    insert_student

    # act
    get LIST, headers: as(1)
    submit = dom.at_css("details.lb-menu button[type=submit], details.lb-menu input[type=submit]")

    # assert
    assert submit
    assert_equal label(:apply_filter), (submit["value"] || submit.text).strip
  end

  def test_search_field_and_submit_share_the_query_form_and_the_label_has_a_magnifier
    # arrange
    classify_and_reveal
    insert_student

    # act
    get LIST, headers: as(1)
    form = dom.at_css("form.lb-query-form")
    search = form.at_css("input[type=search]")
    submit = form.css("button[type=submit], input[type=submit]").find { |node| (node["value"] || node.text).strip == label(:search) }

    # assert
    assert search
    assert submit
    assert form.at_css("label.lb-search svg")
    assert_includes form.css("label.lb-search input[type=search]").map { |node| node["name"] }, search["name"]
  end

  def test_apply_filter_locale_key_exists_in_both_languages
    # arrange
    key = "lucid_backoffice.apply_filter"

    # act
    missing = %i[en pt-BR].reject { |locale| I18n.exists?(key, locale) }

    # assert
    assert_empty missing
    assert_equal "Aplicar filtro", I18n.t(key, locale: :"pt-BR")
    assert_equal "Apply filter", I18n.t(key, locale: :en)
  end

  def list_cell_nodes(column)
    index = dom.css("thead th").index { |th| th.children.first.text.strip == column }
    dom.css("tbody tr").first.css("td")[index].css(".lb-value")
  end

  def detail_cell_nodes(column)
    term = dom.css("dt").find { |dt| dt.children.first.text.strip == column }
    term.next_element.css(".lb-value")
  end

  def test_list_marks_revealed_values_and_only_those
    # arrange
    classify_and_reveal
    insert_student

    # act
    get LIST, headers: as(1)
    contact = list_cell_nodes("email")
    public_cell = list_cell_nodes("owner_type")
    documents = list_cell_nodes("cpf")

    # assert
    refute_empty contact
    assert contact.all? { |node| node.key?("data-lb-revealed") }
    refute_empty public_cell
    refute public_cell.any? { |node| node.key?("data-lb-revealed") }
    refute_empty documents
    assert documents.all? { |node| node["class"].split.include?("lb-masked") && !node.key?("data-lb-revealed") }
  end

  def test_detail_marks_revealed_values_and_only_those
    # arrange
    classify_and_reveal
    insert_student

    # act
    get "/backoffice/data/students/1", headers: as(1)
    contact = detail_cell_nodes("email")
    public_cell = detail_cell_nodes("owner_type")
    documents = detail_cell_nodes("cpf")

    # assert
    refute_empty contact
    assert contact.all? { |node| node.key?("data-lb-revealed") }
    refute_empty public_cell
    refute public_cell.any? { |node| node.key?("data-lb-revealed") }
    refute_empty documents
    assert documents.all? { |node| node["class"].split.include?("lb-masked") && !node.key?("data-lb-revealed") }
  end

  def test_nothing_is_marked_as_revealed_without_a_reveal
    # arrange
    classify_and_reveal(reveal: false)
    insert_student

    # act
    get LIST, headers: as(1)
    in_list = dom.css("[data-lb-revealed]")
    get "/backoffice/data/students/1", headers: as(1)
    in_detail = dom.css("[data-lb-revealed]")

    # assert
    assert_empty in_list
    assert_empty in_detail
  end

  def test_foreign_key_link_over_a_revealed_column_is_marked
    # arrange
    path = write_yaml("students:\n  tutor: contact\n")
    configure_panel(permissions: { 1 => %i[browse reveal view_activity] }) { |config| config.classification_path = path }
    Lucid::Backoffice::Reveal.grant(operator: PanelOperator.new(1), category: "contact", reason: "investigar chamado 123")
    link_fixture
    connection.execute("ALTER TABLE public.students ADD COLUMN tutor bigint REFERENCES public.guardians (id)")
    insert_student(tutor: 43)

    # act
    get LIST, headers: as(1)
    list_link = dom.at_css("tbody a[href$='/guardians/43']")
    get "/backoffice/data/students/1", headers: as(1)
    detail_link = dom.at_css("dd a[href$='/guardians/43']")

    # assert
    assert list_link.key?("data-lb-revealed")
    assert detail_link.key?("data-lb-revealed")
  end

  def test_foreign_key_link_over_a_public_column_is_not_marked
    # arrange
    classify_and_reveal
    link_fixture
    insert_student(guardian_id: 42)

    # act
    get LIST, headers: as(1)
    list_link = dom.at_css("tbody a[href$='/guardians/42']")

    # assert
    assert list_link
    refute list_link.key?("data-lb-revealed")
  end

  def test_filter_chip_over_a_revealed_column_is_marked_and_over_a_public_column_is_not
    # arrange
    classify_and_reveal
    insert_student(email: "alvo@x.test")

    # act
    run_query(criteria: { filters: { email: "alvo@x.test", guardian_id: "42" } })
    chips = dom.css(".lb-chip").to_h { |chip| [chip.text.include?("email") ? "email" : "guardian_id", chip.at_css("span")] }

    # assert
    assert_equal %w[email guardian_id], chips.keys.sort
    assert chips["email"].key?("data-lb-revealed")
    refute chips["guardian_id"].key?("data-lb-revealed")
  end

  def test_query_bar_has_no_duplicate_ids
    # arrange
    classify_and_reveal
    insert_student(email: "alvo@x.test")

    # act
    run_query(criteria: { search: "a", sort: "id", dir: "asc", filters: { email: "alvo@x.test", guardian_id: "42" } })
    ids = dom.css("[id]").map { |node| node["id"] }

    # assert
    assert_equal ids.uniq, ids
  end
end
