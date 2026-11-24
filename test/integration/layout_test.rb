require "integration_helper"

class LayoutIntegrationTest < PanelTest
  ALL = %i[view_dashboard view_tenant browse view_activity reveal view_errors].freeze

  def setup
    super
    create_tenant_schemas
  end

  def configure_multi(permissions: { 1 => ALL }, &block)
    configure_panel(permissions: permissions, tenancy: FakeTenancy.new) do |config|
      config.sign_out_path = -> { "/logout" }
      block&.call(config)
    end
  end

  def register_plugin
    Lucid::Backoffice.register(:errors) do |panel|
      panel.permission :view_errors
      panel.menu(label: "Erros", path: "/backoffice/errors", permission: :view_errors)
    end
  end

  def shared(key) = I18n.t("lucid_backoffice.#{key}", raise: true)
  def sidebar = dom.at_css("aside.lb-sidebar")
  def context = dom.at_css("aside.lb-sidebar .lb-context")
  def table_links = dom.css("aside.lb-sidebar .lb-nav-data a.lb-nav-table").map { |a| [a.text.strip, a["href"]] }
  def nav_links = dom.css("aside.lb-sidebar nav a:not(.lb-nav-table)").map { |a| [a.text.strip, a["href"]] }
  def switch_links = dom.css("details.lb-context-switch a").map { |a| [a["href"], a.text.strip] }

  def css_block(source, header)
    start = source.index(header)
    return unless start

    depth = 0
    source[start..].each_char.with_index do |char, index|
      depth += 1 if char == "{"
      depth -= 1 if char == "}"
      return source[start..(start + index)] if depth.zero? && char == "}"
    end
  end

  def test_shared_context_card_shows_shared_label_and_schema_name
    # arrange
    configure_multi

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_response :ok
    assert_includes context.text, shared(:shared)
    assert_equal "public", dom.at_css(".lb-context .lb-context-schema").text.strip
    assert_nil dom.at_css("a.lb-context-leave")
  end

  def test_shared_sidebar_lists_overview_activity_plugin_items_and_shared_tables
    # arrange
    configure_multi
    register_plugin

    # act
    get "/backoffice", headers: as(1)

    # assert
    hrefs = nav_links.map(&:last)
    assert_includes nav_links, [shared(:overview), "/backoffice"]
    assert_includes nav_links, [shared(:activity), "/backoffice/activity"]
    assert_includes nav_links, ["Erros", "/backoffice/errors"]
    assert_includes table_links, ["guardians", "/backoffice/data/guardians"]
    assert_includes table_links, ["students", "/backoffice/data/students"]
    assert_empty hrefs.grep(%r{/tenants/})
  end

  def test_shared_tables_exclude_hidden_and_internal_tables
    # arrange
    configure_multi { |config| config.hidden_tables = %w[guardians] }

    # act
    get "/backoffice", headers: as(1)

    # assert
    names = table_links.map(&:first)
    assert_includes names, "students"
    refute_includes names, "guardians"
    assert_empty names.grep(/\Alucid_backoffice_|\Aschema_migrations\z|\Aar_internal_metadata\z/)
  end

  def test_brand_title_stays_in_the_sidebar
    # arrange
    configure_multi { |config| config.title = "Luneta Ops" }

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_equal "Luneta Ops", sidebar.at_css(".lb-brand").text.strip
  end

  def test_old_top_nav_is_gone
    # arrange
    configure_multi

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_nil dom.at_css("nav.lb-nav")
    assert_nil dom.at_css(".lb-nav")
  end

  def test_current_page_item_has_aria_current_page
    # arrange
    configure_multi

    # act
    get "/backoffice/activity", headers: as(1)
    activity_current = dom.css("aside.lb-sidebar [aria-current=page]").map { |a| a["href"] }
    get "/backoffice", headers: as(1)
    root_current = dom.css("aside.lb-sidebar [aria-current=page]").map { |a| a["href"] }

    # assert
    assert_equal ["/backoffice/activity"], activity_current
    assert_equal ["/backoffice"], root_current
  end

  def test_current_table_item_has_aria_current_page
    # arrange
    configure_multi

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_equal ["/backoffice/data/students"], dom.css("aside.lb-sidebar [aria-current=page]").map { |a| a["href"] }
  end

  def test_topbar_has_breadcrumbs_then_sign_out
    # arrange
    configure_multi

    # act
    get "/backoffice", headers: as(1)

    # assert
    topbar = dom.at_css("header.lb-topbar")
    assert topbar.at_css(".lb-crumbs")
    assert_equal "/logout", topbar.at_css("a.lb-signout")["href"]
    assert_nil sidebar.at_css(".lb-signout")
    children = topbar.css(".lb-crumbs, .lb-signout").map { |node| node["class"].split.first }
    assert_equal %w[lb-crumbs lb-signout], children
  end

  def test_multi_tenant_shared_context_offers_entering_a_tenant
    # arrange
    configure_multi

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_equal [["/backoffice/tenants/alfa", "Escola alfa"], ["/backoffice/tenants/beta", "Escola beta"]], switch_links
  end

  def test_switch_lists_only_tenants_the_operator_may_view
    # arrange
    configure_multi do |config|
      config.authorize = lambda do |_operator, permission, context|
        next true unless permission == :view_tenant

        context[:tenant].nil? || context[:tenant].code == "alfa"
      end
    end

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_equal ["/backoffice/tenants/alfa"], switch_links.map(&:first)
  end

  def test_tenant_context_card_shows_label_leave_and_switch
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_includes context.text, "Escola alfa"
    refute_includes context.text, shared(:shared)
    leave = dom.at_css("a.lb-context-leave")
    assert_equal "/backoffice", leave["href"]
    assert_equal shared(:leave_tenant), leave.text.strip
    assert dom.at_css("details.lb-context-switch")
    assert_includes dom.at_css("details.lb-context-switch summary").text, shared(:switch_context)
    assert_includes switch_links.map(&:first), "/backoffice/tenants/beta"
  end

  def test_tenant_sidebar_has_overview_activity_and_tenant_tables_only
    # arrange
    configure_multi
    register_plugin

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_includes nav_links, [shared(:tenant_overview), "/backoffice/tenants/alfa"]
    assert_includes nav_links, [shared(:activity), "/backoffice/tenants/alfa/activity"]
    assert_equal ["/backoffice/tenants/alfa/data/guardians", "/backoffice/tenants/alfa/data/students"], table_links.map(&:last).sort
    refute_includes nav_links.map(&:first), "Erros"
    refute_includes nav_links.map(&:last), "/backoffice/activity"
    refute_includes nav_links.map(&:last), "/backoffice"
  end

  def test_tenant_context_persists_on_nested_pages
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa/data/students", headers: as(1)
    on_table = [dom.at_css("a.lb-context-leave") && true, context.text.include?("Escola alfa"), nav_links.map(&:last).include?("/backoffice/tenants/alfa/activity")]
    get "/backoffice/tenants/beta/activity", headers: as(1)

    # assert
    assert_equal [true, true, true], on_table
    assert_includes context.text, "Escola beta"
    assert_equal ["/backoffice/tenants/beta/activity"], dom.css("aside.lb-sidebar [aria-current=page]").map { |a| a["href"] }
  end

  def test_data_section_is_hidden_without_browse
    # arrange
    configure_multi(permissions: { 1 => %i[view_dashboard view_tenant view_activity] })

    # act
    get "/backoffice", headers: as(1)
    shared_data = dom.css(".lb-nav-data, a.lb-nav-table").size
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_equal 0, shared_data
    assert_equal 0, dom.css(".lb-nav-data, a.lb-nav-table").size
  end

  def test_activity_item_is_hidden_without_view_activity
    # arrange
    configure_multi(permissions: { 1 => %i[view_dashboard view_tenant browse] })

    # act
    get "/backoffice", headers: as(1)
    shared_hrefs = nav_links.map(&:last)
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    refute_includes shared_hrefs, "/backoffice/activity"
    refute_includes nav_links.map(&:last), "/backoffice/tenants/alfa/activity"
  end

  def test_sidebar_activity_item_follows_the_per_tenant_authorization
    # arrange
    configure_multi do |config|
      config.authorize = lambda do |_operator, permission, context|
        next true unless permission == :view_activity

        context[:tenant]&.code != "beta"
      end
    end

    # act
    get "/backoffice/tenants/beta", headers: as(1)
    in_beta = nav_links.map(&:last)
    get "/backoffice/tenants/alfa", headers: as(1)
    in_alfa = nav_links.map(&:last)

    # assert
    refute_includes in_beta, "/backoffice/tenants/beta/activity"
    assert_includes in_alfa, "/backoffice/tenants/alfa/activity"
  end

  def with_tables(*names)
    names.each { |name| connection.execute("CREATE TABLE public.#{name} (id bigserial PRIMARY KEY)") }
    yield
  ensure
    names.each { |name| connection.execute("DROP TABLE IF EXISTS public.#{name}") }
  end

  def test_current_table_marker_does_not_leak_to_tables_sharing_a_prefix
    # arrange
    configure_multi

    # act
    with_tables("users", "user", "users_archive") do
      get "/backoffice/data/users", headers: as(1)
    end

    # assert
    assert_equal ["/backoffice/data/users"], dom.css("aside.lb-sidebar [aria-current=page]").map { |a| a["href"] }
    assert_equal %w[user users users_archive], table_links.map(&:first).grep(/\Auser/).sort
  end

  def test_current_marker_on_a_longer_table_does_not_mark_the_shorter_one
    # arrange
    configure_multi

    # act
    with_tables("users", "users_archive") do
      get "/backoffice/data/users_archive", headers: as(1)
    end

    # assert
    assert_equal ["/backoffice/data/users_archive"], dom.css("aside.lb-sidebar [aria-current=page]").map { |a| a["href"] }
  end

  def lb_current(path_info, target, **options)
    controller = Lucid::Backoffice::ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create("PATH_INFO" => path_info, "SCRIPT_NAME" => "")
    controller.send(:lb_current?, target, **options)
  end

  def test_overview_is_current_when_the_panel_is_mounted_at_the_root
    # arrange
    root = "/"

    # act
    current = lb_current(root, root)

    # assert
    assert current
  end

  def test_overview_is_not_current_on_another_path_when_mounted_at_the_root
    # arrange
    path = "/activity"

    # act
    current = lb_current(path, "/")

    # assert
    refute current
  end

  def test_overview_item_is_hidden_without_view_dashboard
    # arrange
    configure_multi(permissions: { 1 => %i[browse view_activity] })

    # act
    get "/backoffice/data", headers: as(1)

    # assert
    refute_includes nav_links.map(&:last), "/backoffice"
    assert_includes nav_links.map(&:last), "/backoffice/activity"
  end

  def test_plugin_item_is_hidden_without_its_permission
    # arrange
    configure_multi(permissions: { 1 => %i[view_dashboard browse] })
    register_plugin

    # act
    get "/backoffice", headers: as(1)

    # assert
    refute_includes nav_links.map(&:first), "Erros"
  end

  def test_panel_without_tenancy_shows_only_the_shared_context
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard browse view_activity reveal] }) { |config| config.tenancy = :none }

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_includes context.text, shared(:shared)
    assert dom.at_css(".lb-context .lb-context-schema")
    assert_nil dom.at_css("details.lb-context-switch")
    assert_nil dom.at_css("a.lb-context-leave")
    assert_includes table_links.map(&:first), "guardians"
    assert_includes table_links.map(&:first), "students"
    assert_empty table_links.map(&:first).grep(/\Alucid_backoffice_|\Aschema_migrations\z|\Aar_internal_metadata\z/)
  end

  def test_panel_without_tenancy_never_mentions_tenant
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard browse view_activity reveal] }) { |config| config.tenancy = :none }
    insert_student
    Lucid::Backoffice::Activity::Event.create!(name: "widget.created", actor_type: "System", occurred_at: Time.current)

    # act
    texts = %w[/backoffice /backoffice/data /backoffice/data/students /backoffice/activity].to_h do |path|
      get path, headers: as(1)
      [path, dom.text]
    end

    # assert
    texts.each { |path, text| refute_match(/tenant/i, text, "#{path} mentions tenant") }
  end

  def test_sidebar_is_wrapped_in_a_mobile_toggle_with_a_menu_summary
    # arrange
    configure_multi

    # act
    get "/backoffice", headers: as(1)

    # assert
    toggle = dom.at_css("details.lb-sidebar-toggle")
    assert toggle
    assert_equal shared(:menu), toggle.at_css("summary").text.strip
    assert toggle.at_css("aside.lb-sidebar")
  end

  def test_css_collapses_the_sidebar_behind_the_toggle_on_narrow_screens
    # arrange
    path = "/backoffice/assets/lucid_backoffice.css"

    # act
    get path
    block = css_block(response.body, "@media (max-width: 40rem)")

    # assert
    assert block, "missing @media (max-width: 40rem)"
    assert_includes block, ".lb-sidebar-toggle"
  end
end
