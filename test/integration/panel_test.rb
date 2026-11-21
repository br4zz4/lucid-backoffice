require "integration_helper"

class PanelIntegrationTest < PanelTest
  Plugin = Struct.new(:cards)

  def setup
    super
    @periods = []
  end

  def register_app(permission: :view_dashboard)
    periods = @periods
    Lucid::Backoffice.register(:app) do |panel|
      panel.card(:students_total, label: "Alunos", permission: permission, value: lambda { |period|
        periods << period
        connection_count = ActiveRecord::Base.lease_connection.select_value(
          "SELECT COUNT(*) FROM students WHERE created_at BETWEEN #{ActiveRecord::Base.connection.quote(period.range.begin)} " \
          "AND #{ActiveRecord::Base.connection.quote(period.range.end)}"
        )
        connection_count.to_i
      })
      panel.menu(label: "Escolas", path: "/backoffice-app/organizations", permission: :manage_organizations)
    end
  end

  def register_plugin
    Lucid::Backoffice.register(:errors) do |panel|
      panel.permission :view_errors
      panel.menu(label: "Erros", path: "/backoffice/errors", permission: :view_errors)
      panel.card(:errors_total, label: "Erros", permission: :view_errors, value: ->(_period) { 5 })
      panel.tenant_section(:errors, partial: "plugin_errors/section", permission: :view_errors)
    end
  end

  def card_texts = dom.css(".lb-card").map { |card| card.text.squish }
  def nav_labels = dom.css("nav.lb-nav a").map { |a| a.text.strip }

  def test_dashboard_card_value_receives_week_period_by_default
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard] })
    register_app
    insert_student(created_at: 2.days.ago)
    insert_student(created_at: 20.days.ago)

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_equal ["Alunos 1"], card_texts
    assert_equal "week", @periods.sole.key
    assert_in_delta 7.days.to_f, @periods.sole.range.end - @periods.sole.range.begin, 5
  end

  def test_dashboard_period_toggle_changes_the_range
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard] })
    register_app
    insert_student(created_at: 2.days.ago)
    insert_student(created_at: 20.days.ago)

    # act
    get "/backoffice", params: { period: "month" }, headers: as(1)

    # assert
    assert_equal ["Alunos 2"], card_texts
    assert_equal "month", @periods.sole.key
    assert_in_delta 30.days.to_f, @periods.sole.range.end - @periods.sole.range.begin, 5
    assert_equal "lb-active", dom.css("p.lb-period a")[1]["class"]
    assert_equal ["period=week", "period=month"], dom.css("p.lb-period a").map { |a| URI(a["href"]).query }
  end

  def test_dashboard_card_is_hidden_without_its_permission
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard] })
    register_app(permission: :view_students_total)

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_response :ok
    assert_empty card_texts
    assert_empty @periods
  end

  def test_dashboard_card_is_shown_with_its_permission
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard view_students_total] })
    register_app(permission: :view_students_total)

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_equal ["Alunos 0"], card_texts
  end

  def test_dashboard_lists_tenants_with_label_only_with_view_tenant
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard view_tenant], 2 => %i[view_dashboard] }, tenancy: FakeTenancy.new)

    # act
    get "/backoffice", headers: as(1)
    with = dom.css("ul.lb-list li").map { |li| li.text.squish }
    get "/backoffice", headers: as(2)

    # assert
    assert_equal ["Escola alfa alfa", "Escola beta beta"], with
    assert_empty dom.css("ul.lb-list")
  end

  def test_menu_item_shows_only_with_permission
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard manage_organizations], 2 => %i[view_dashboard] })
    register_app

    # act
    get "/backoffice", headers: as(1)
    allowed = nav_labels
    get "/backoffice", headers: as(2)

    # assert
    assert_includes allowed, "Escolas"
    refute_includes nav_labels, "Escolas"
  end

  def test_nav_shows_data_and_activity_only_with_permissions
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard browse view_activity], 2 => %i[view_dashboard] })

    # act
    get "/backoffice", headers: as(1)
    full = nav_labels
    get "/backoffice", headers: as(2)

    # assert
    assert_equal %w[Data Activity], full.last(2)
    assert_equal ["Back office"], nav_labels
  end

  def test_plugin_menu_card_and_section_appear_for_operator_with_permission
    # arrange
    create_tenant_schemas
    configure_panel(permissions: { 1 => %i[view_dashboard view_tenant view_errors] }, tenancy: FakeTenancy.new)
    register_plugin

    # act
    get "/backoffice", headers: as(1)
    dashboard_menu = nav_labels
    dashboard_cards = card_texts
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_includes dashboard_menu, "Erros"
    assert_equal ["Erros 5"], dashboard_cards
    assert_equal "Erros de alfa", dom.at_css("#errors-section").text
    assert_includes Lucid::Backoffice::Registry.permissions, :view_errors
  end

  def test_plugin_pieces_are_hidden_without_the_permission
    # arrange
    create_tenant_schemas
    configure_panel(permissions: { 1 => %i[view_dashboard view_tenant] }, tenancy: FakeTenancy.new)
    register_plugin

    # act
    get "/backoffice", headers: as(1)
    menu = nav_labels
    cards = card_texts
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    refute_includes menu, "Erros"
    assert_empty cards
    assert_nil dom.at_css("#errors-section")
  end

  def test_app_screen_inherits_layout_authentication_and_authorization
    # arrange
    configure_panel(permissions: { 1 => %i[manage_organizations view_dashboard], 2 => %i[view_dashboard] })
    register_app

    # act
    get "/backoffice-app/organizations"
    anonymous = [response.status, @authenticate_calls]
    get "/backoffice-app/organizations", headers: as(2)
    denied = response.status
    get "/backoffice-app/organizations", headers: as(1)

    # assert
    assert_equal [302, 1], anonymous
    assert_equal 403, denied
    assert_response :ok
    assert_equal "Escolas", dom.at_css("main.lb-main h1").text
    assert dom.at_css("nav.lb-nav a.lb-brand")
    assert dom.at_css("link[href='/backoffice/assets/lucid_backoffice.css']")
    assert_includes nav_labels, "Escolas"
  end

  def test_config_layout_overrides_the_layout
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard] }) { |config| config.layout = "dummy_layout" }

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert dom.at_css("#custom")
    assert_nil dom.at_css("nav.lb-nav")
  end

  def test_app_view_path_overrides_the_gem_partial
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard] })
    register_plugin
    override = File.expand_path("../dummy/override_views", __dir__)
    original = ActionController::Base.view_paths
    ActionController::Base.prepend_view_path(override)
    Lucid::Backoffice.register(:errors) { |panel| panel.card(:errors_total, label: "Erros", value: ->(_period) { 5 }) }

    # act
    begin
      get "/backoffice", headers: as(1)
    ensure
      ActionController::Base.view_paths = original
    end

    # assert
    assert_equal ["Erros=5"], dom.css(".app-card").map(&:text)
    assert_empty dom.css(".lb-card")
  end

  def test_gem_partial_is_used_without_the_override
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard] })
    Lucid::Backoffice.register(:errors) { |panel| panel.card(:errors_total, label: "Erros", value: ->(_period) { 5 }) }

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_empty dom.css(".app-card")
    assert_equal 1, dom.css(".lb-card").size
  end

  def test_css_asset_is_served_without_authentication
    # arrange
    path = "/backoffice/assets/lucid_backoffice.css"

    # act
    get path

    # assert
    assert_response :ok
    assert_equal "text/css", response.media_type
    assert_includes response.body, "--lb-brand"
    refute_match(/tailwind|stimulus/i, response.body)
  end

  def test_js_asset_is_served_without_authentication
    # arrange
    path = "/backoffice/assets/lucid_backoffice.js"

    # act
    get path

    # assert
    assert_response :ok
    assert_match(%r{javascript}, response.media_type)
    refute_match(/tailwind|stimulus/i, response.body)
  end

  def test_other_asset_names_are_not_served
    # arrange
    paths = ["/backoffice/assets/other.css", "/backoffice/assets/..%2Fengine.rb", "/backoffice/assets/lucid_backoffice.css.rb"]

    # act
    results = paths.map do
      begin
        get _1
        response.status
      rescue ActionController::RoutingError
        404
      end
    end

    # assert
    assert_equal [404] * 3, results
  end

  def test_brand_color_and_title_come_from_configuration
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard] }) do |config|
      config.brand_color = "#ff0066"
      config.title = "Luneta Ops"
    end

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_includes dom.at_css("style").text, "#ff0066"
    assert_equal "Luneta Ops", dom.at_css("title").text
  end

  def test_layout_uses_no_tailwind_or_stimulus
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard browse] })

    # act
    get "/backoffice", headers: as(1)

    # assert
    refute_match(/tailwind|stimulus|data-controller/i, response.body)
  end

  def test_sign_out_link_uses_configured_path
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard] }) { |config| config.sign_out_path = -> { "/logout" } }

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_equal "/logout", dom.at_css("a.lb-signout")["href"]
  end

  def test_pt_br_locale_translates_the_panel
    # arrange
    configure_panel(permissions: { 1 => %i[view_dashboard browse view_activity] })
    register_app

    # act
    I18n.with_locale(:"pt-BR") { get "/backoffice", headers: as(1) }

    # assert
    assert_includes nav_labels, "Dados"
    assert_includes nav_labels, "Atividade"
    assert_equal ["Semana", "Mês"], dom.css("p.lb-period a").map(&:text)
    assert_equal "pt-BR", dom.at_css("html")["lang"]
  end

  def test_activity_screen_renders_in_pt_br_without_extra_gems
    # arrange
    configure_panel(permissions: { 1 => %i[view_activity] })
    Lucid::Backoffice::Activity::Event.create!(name: "x.y", actor_type: "System", occurred_at: Time.current)

    # act
    I18n.with_locale(:"pt-BR") { get "/backoffice/activity", headers: as(1) }

    # assert
    assert_response :ok
    assert_includes response.body, "x.y"
  end

  def test_activity_screen_renders_in_en
    # arrange
    configure_panel(permissions: { 1 => %i[view_activity] })
    Lucid::Backoffice::Activity::Event.create!(name: "x.y", actor_type: "System", occurred_at: Time.current)

    # act
    I18n.with_locale(:en) { get "/backoffice/activity", headers: as(1) }

    # assert
    assert_response :ok
    assert_includes nav_labels, "Activity"
  end

  def test_en_and_pt_br_define_the_same_keys
    # arrange
    flatten = lambda do |hash, prefix = nil|
      hash.flat_map { |key, value| value.is_a?(Hash) ? flatten.call(value, [prefix, key].compact.join(".")) : [[prefix, key].compact.join(".")] }
    end

    # act
    en = flatten.call(I18n.backend.translations[:en][:lucid_backoffice])
    pt = flatten.call(I18n.backend.translations[:"pt-BR"][:lucid_backoffice])

    # assert
    assert_empty en - pt
    assert_empty pt - en
    assert_operator en.size, :>, 10
  end
end
