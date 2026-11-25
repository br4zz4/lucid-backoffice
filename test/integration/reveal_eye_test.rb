require "integration_helper"

class RevealEyeIntegrationTest < PanelTest
  REASON = "investigar chamado 123".freeze
  ALL = %i[view_dashboard view_tenant browse reveal view_activity].freeze

  def setup
    super
    create_tenant_schemas
  end

  def configure_multi(permissions: { 1 => ALL, 2 => ALL, 3 => %i[view_dashboard view_tenant browse] }, &block)
    configure_panel(permissions: permissions, tenancy: FakeTenancy.new) do |config|
      config.sign_out_path = -> { "/logout" }
      block&.call(config)
    end
  end

  def configure_single(permissions: { 1 => ALL })
    configure_panel(permissions: permissions) do |config|
      config.tenancy = :none
      config.sign_out_path = -> { "/logout" }
    end
  end

  def tenant(identifier) = FakeTenancy.new.find(identifier)

  def grant(category, tenant: "alfa", operator: 1, expires_in: nil)
    reveal = Lucid::Backoffice::Reveal.grant(operator: PanelOperator.new(operator), category: category, reason: REASON, tenant: tenant && tenant(tenant))
    reveal.update_columns(expires_at: expires_in.from_now) if expires_in
    reveal
  end

  def label(key, **options) = I18n.t("lucid_backoffice.#{key}", **options, raise: true)
  def minutes = Lucid::Backoffice.configuration.reveal_duration / 60
  def clock(time) = I18n.l(time.in_time_zone, format: "%H:%M")
  def eye = dom.at_css("header.lb-topbar .lb-topbar-right .lb-eye")
  def eye_dialog = dom.at_css("div.lb-reveal-dialog")
  def reveal_form = eye_dialog.at_css("form[data-lb-reason-form]")
  def end_form = dom.at_css("header.lb-topbar form.button_to[action='/backoffice/reveals']")

  def test_eye_sits_in_the_topbar_before_sign_out
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    right = dom.at_css("header.lb-topbar .lb-topbar-right")
    order = right.css(".lb-eye, .lb-signout").map { |node| node["class"].split.first }
    assert_equal %w[lb-eye lb-signout], order
  end

  def test_masked_eye_shows_masked_label_and_opens_the_dialog
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_equal "summary", eye.name
    assert_equal "details", eye.parent.name
    assert_includes eye.parent["class"].split, "lb-eye-pop"
    assert_predicate eye["title"], :present?
    assert_equal label(:masked_data), eye.at_css(".lb-eye-label").text.strip
    refute_includes eye["class"].split, "lb-eye-on"
    assert_nil end_form
  end

  def test_dialog_title_names_the_tenant_context
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_equal label(:reveal_title_in, context: "Escola alfa"), eye_dialog.at_css("h2").text.strip
  end

  def test_dialog_title_has_no_context_without_tenancy
    # arrange
    configure_single

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_equal label(:reveal_title), eye_dialog.at_css("h2").text.strip
  end

  def test_dialog_form_posts_one_reason_with_no_category
    # arrange
    configure_multi { |config| config.reveal_reason_min = 12 }

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    form = reveal_form
    assert_equal "/backoffice/reveals", form["action"]
    assert_equal "post", form["method"].downcase
    textarea = form.at_css("textarea[name=reason][data-lb-reason]")
    assert_equal "12", textarea["minlength"]
    assert textarea.key?("required")
    assert_equal "alfa", form.at_css("input[type=hidden][name=tenant_id]")["value"]
    assert_empty form.css("[name=category]")
  end

  def test_dialog_submit_is_enabled_without_js_and_states_the_duration
    # arrange
    configure_multi { |config| config.reveal_duration = 30 * 60 }

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    submit = reveal_form.at_css("[data-lb-submit]")
    refute submit.key?("disabled")
    assert_equal label(:reveal_all, minutes: 30), (submit["value"] || submit.text).strip
  end

  def test_dialog_has_explainer_and_no_cancel_or_native_dialog
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_empty dom.css("dialog")
    assert_empty eye_dialog.css("button[data-lb-reveal-close]")
    assert_includes eye_dialog.css("p").map { |p| p.text.squish }, label(:reveal_explainer, minutes: minutes)
  end

  def test_dialog_lists_every_category_except_public
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    expected = Lucid::Backoffice.configuration.categories - ["public"]
    assert_equal expected.sort, eye_dialog.css(".lb-reveal-categories .lb-tag").map { |tag| tag.text.strip }.sort
  end

  def test_shared_context_form_sends_no_tenant
    # arrange
    configure_single

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_predicate reveal_form.at_css("input[name=tenant_id]")&.[]("value").to_s, :empty?
  end

  def test_eye_is_absent_without_the_reveal_permission
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa", headers: as(3)
    shared = [dom.css(".lb-eye").size, dom.css("div.lb-reveal-dialog").size]
    get "/backoffice", headers: as(3)

    # assert
    assert_equal [0, 0], shared
    assert_empty dom.css(".lb-eye")
    assert_empty dom.css("div.lb-reveal-dialog")
  end

  def test_eye_is_absent_without_the_reveal_permission_and_without_tenancy
    # arrange
    configure_single(permissions: { 1 => %i[view_dashboard browse] })

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_empty dom.css(".lb-eye")
    assert_empty dom.css("div.lb-reveal-dialog")
  end

  def test_active_reveal_turns_the_eye_on_with_the_earliest_expiry
    # arrange
    configure_multi
    grant("contact", expires_in: 20.minutes)
    soonest = grant("documents", expires_in: 5.minutes)

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_includes eye["class"].split, "lb-eye-on"
    assert_includes eye.text.squish, label(:revealed_until, time: clock(soonest.reload.expires_at))
    assert_nil eye_dialog
  end

  def test_active_eye_ends_all_with_a_delete_form
    # arrange
    configure_multi
    grant("contact")

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_equal "post", end_form["method"].downcase
    assert_equal "delete", end_form.at_css("input[name=_method]")["value"]
    assert_equal "alfa", end_form.at_css("input[name=tenant_id]")["value"]
    assert_includes (end_form.at_css("button, input[type=submit]")["value"] || end_form.text).to_s, label(:end_reveal_all)
  end

  def test_ending_all_reveals_restores_the_masked_eye
    # arrange
    configure_multi
    grant("contact")
    grant("documents")

    # act
    delete "/backoffice/reveals", params: { tenant_id: "alfa" }, headers: as(1)
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_equal 0, Lucid::Backoffice::Reveal.active.count
    assert_includes eye.text, label(:masked_data)
    assert eye_dialog
  end

  def test_ending_an_active_reveal_keeps_the_ended_notice
    # arrange
    configure_multi
    grant("contact")

    # act
    delete "/backoffice/reveals", params: { tenant_id: "alfa" }, headers: as(1)
    follow_redirect!(headers: as(1))

    # assert
    assert_equal label(:revoked), dom.at_css(".lb-flash-ok").text.strip
  end

  def test_ending_without_an_active_reveal_redirects_without_notice_or_event
    # arrange
    configure_multi

    # act
    delete "/backoffice/reveals", params: { tenant_id: "alfa" }, headers: as(1)
    status = response.status
    follow_redirect!(headers: as(1))

    # assert
    assert_equal 302, status
    assert_empty dom.css(".lb-flash-ok")
    assert_empty events("backoffice.reveal.revoke")
  end

  def test_shared_context_is_named_home
    # arrange
    configure_multi

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_equal "Home", I18n.t("lucid_backoffice.shared", locale: :en)
    assert_equal "Home", I18n.t("lucid_backoffice.shared", locale: :"pt-BR")
    assert_includes dom.text, label(:shared)
  end

  def test_reveal_eye_is_scoped_to_the_context
    # arrange
    configure_multi
    reveal = grant("contact", tenant: "alfa")

    # act
    get "/backoffice/tenants/beta", headers: as(1)
    in_beta = [eye.text.squish, eye["class"].split.include?("lb-eye-on")]
    beta_dialog = !eye_dialog.nil?
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_includes in_beta.first, label(:masked_data)
    refute in_beta.last
    assert beta_dialog
    assert_includes eye.text.squish, label(:revealed_until, time: clock(reveal.reload.expires_at))
  end

  def test_shared_context_does_not_inherit_a_tenant_reveal
    # arrange
    configure_multi
    grant("contact", tenant: "alfa")

    # act
    get "/backoffice", headers: as(1)

    # assert
    refute_includes eye["class"].split, "lb-eye-on"
    assert eye_dialog
  end

  def authorize_categories(allowed)
    ->(_operator, permission, context) { permission == :reveal ? (context.key?(:category) && allowed.include?(context[:category])) : true }
  end

  def test_eye_is_absent_when_every_category_is_denied
    # arrange
    allowed = authorize_categories([])
    configure_multi { |config| config.authorize = allowed }

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_empty dom.css(".lb-eye")
    assert_empty dom.css("div.lb-reveal-dialog")
  end

  def test_eye_is_absent_when_every_category_is_denied_without_tenancy
    # arrange
    allowed = authorize_categories([])
    configure_panel { |config| config.tenancy = :none; config.authorize = allowed }

    # act
    get "/backoffice", headers: as(1)

    # assert
    assert_empty dom.css(".lb-eye")
    assert_empty dom.css("div.lb-reveal-dialog")
  end

  def test_dialog_lists_only_the_categories_the_operator_may_reveal
    # arrange
    allowed = authorize_categories(%w[contact documents])
    configure_multi { |config| config.authorize = allowed }

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert eye
    assert_equal %w[contact documents], eye_dialog.css(".lb-reveal-categories .lb-tag").map { |tag| tag.text.strip }.sort
  end

  def test_eye_shows_with_a_single_revealable_category
    # arrange
    allowed = authorize_categories(%w[contact])
    configure_multi { |config| config.authorize = allowed }

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert eye
    assert_equal %w[contact], eye_dialog.css(".lb-reveal-categories .lb-tag").map { |tag| tag.text.strip }
  end

  def test_other_operators_reveals_do_not_light_the_eye
    # arrange
    configure_multi
    grant("contact", operator: 2)

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    refute_includes eye["class"].split, "lb-eye-on"
    assert_includes eye.text, label(:masked_data)
  end

  def test_expired_and_revoked_reveals_do_not_light_the_eye
    # arrange
    configure_multi
    grant("contact").update_columns(expires_at: 1.minute.ago)
    grant("documents").update_columns(revoked_at: Time.current)

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    refute_includes eye["class"].split, "lb-eye-on"
    assert eye_dialog
  end

  def test_per_category_list_is_gone_and_the_eye_remains
    # arrange
    configure_multi

    # act
    get "/backoffice/tenants/alfa/data/students", headers: as(1)

    # assert
    assert_empty dom.css("form.lb-reason-form, section.lb-reveal")
    assert eye
  end

  def test_eye_renders_on_every_panel_page
    # arrange
    configure_multi
    paths = %w[/backoffice /backoffice/activity /backoffice/data /backoffice/tenants/alfa /backoffice/tenants/alfa/activity /backoffice/tenants/alfa/data /backoffice/tenants/alfa/data/students]

    # act
    present = paths.to_h do |path|
      get path, headers: as(1)
      [path, dom.css("header.lb-topbar .lb-eye").size]
    end

    # assert
    assert_equal paths.to_h { |path| [path, 1] }, present
  end

  def test_js_keeps_the_reason_form_handler
    # arrange
    path = "/backoffice/assets/lucid_backoffice.js"

    # act
    get path

    # assert
    assert_response :ok
    assert_includes response.body, "data-lb-reason-form"
  end

  def served_css
    get "/backoffice/assets/lucid_backoffice.css"
    response.body
  end

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

  def test_css_styles_the_eye_popover
    # arrange / act
    css = served_css

    # assert
    assert_includes css, ".lb-eye-pop"
  end

  def test_css_hides_the_eye_label_on_narrow_screens
    # arrange / act
    block = css_block(served_css, "@media (max-width: 40rem)")

    # assert
    assert block, "missing @media (max-width: 40rem)"
    assert_match(/\.lb-eye-label[^{]*\{[^}]*display:\s*none/m, block)
  end

  def test_css_keeps_breadcrumbs_on_one_line
    # arrange / act
    css = served_css

    # assert
    assert_match(/\.lb-crumbs[^{]*\{[^}]*white-space:\s*nowrap/m, css)
  end

  def test_css_rounds_the_sidebar_links
    # arrange / act
    css = served_css

    # assert
    assert_match(/\.lb \.lb-sidebar \.lb-nav-main a[^{]*\{[^}]*border-radius/m, css)
  end

  def test_active_eye_exposes_countdown_data_for_the_earliest_expiry
    # arrange
    configure_multi
    soonest = grant("contact", expires_in: 10.minutes)
    grant("documents", expires_in: 14.minutes)

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_includes eye["class"].split, "lb-eye-on"
    assert eye.key?("data-lb-countdown")
    assert_in_delta 600, eye["data-lb-remaining"].to_i, 2
    assert_equal label(:revealed_running, time: "%{time}"), eye["data-lb-label-running"]
    assert_includes eye["data-lb-label-running"], "%{time}"
    assert_equal label(:reveal_expired), eye["data-lb-label-expired"]
    assert_equal label(:revealed_until, time: clock(soonest.reload.expires_at)), eye["title"]
  end

  def test_active_eye_text_without_js_stays_revealed_until
    # arrange
    configure_multi
    soonest = grant("contact", expires_in: 10.minutes)
    grant("documents", expires_in: 14.minutes)

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    countdown_label = eye.at_css("[data-lb-countdown-label]")
    assert countdown_label
    assert_equal label(:revealed_until, time: clock(soonest.reload.expires_at)), countdown_label.text.squish
  end

  def test_countdown_locale_keys_exist_in_both_languages
    # arrange
    keys = %w[revealed_running reveal_expired]

    # act
    missing = %i[en pt-BR].flat_map do |locale|
      keys.reject { |key| I18n.exists?("lucid_backoffice.#{key}", locale) }.map { |key| "#{locale}.#{key}" }
    end

    # assert
    assert_empty missing
  end

  def test_countdown_locale_values
    # arrange / act
    values = {
      "pt-BR running" => I18n.t("lucid_backoffice.revealed_running", locale: :"pt-BR", time: "01:02"),
      "pt-BR expired" => I18n.t("lucid_backoffice.reveal_expired", locale: :"pt-BR"),
      "en running" => I18n.t("lucid_backoffice.revealed_running", locale: :en, time: "01:02"),
      "en expired" => I18n.t("lucid_backoffice.reveal_expired", locale: :en)
    }

    # assert
    assert_equal(
      { "pt-BR running" => "Revelado · 01:02", "pt-BR expired" => "Expirado", "en running" => "Revealed · 01:02", "en expired" => "Expired" },
      values
    )
  end

  def test_js_asset_has_the_countdown_and_dirty_guard
    # arrange
    source = File.read(File.expand_path("../../app/assets/lucid_backoffice.js", __dir__))

    # act / assert
    assert_includes source, "data-lb-countdown"
    assert_includes source, "lbDirty"
    assert_includes source, "lb-expired"
  end

  def test_js_asset_handles_selects_in_the_dirty_guard_and_has_the_submit_fallback_and_aria_pressed
    # arrange
    source = File.read(File.expand_path("../../app/assets/lucid_backoffice.js", __dir__))

    # act / assert
    assert_includes source, "selectedIndex"
    assert_includes source, "form.submit()"
    assert_includes source, "aria-pressed"
  end

  def test_css_asset_styles_the_warn_and_expired_eye
    # arrange
    source = File.read(File.expand_path("../../app/assets/lucid_backoffice.css", __dir__))

    # act / assert
    assert_includes source, ".lb-eye-warn"
    assert_includes source, ".lb-eye-expired"
  end

  def test_new_locale_keys_exist_in_both_languages
    # arrange
    keys = %w[masked_data reveal_title_in reveal_all reveal_explainer revealed_until end_reveal_all cancel]

    # act
    missing = %i[en pt-BR].flat_map do |locale|
      keys.reject { |key| I18n.exists?("lucid_backoffice.#{key}", locale) }.map { |key| "#{locale}.#{key}" }
    end

    # assert
    assert_empty missing
  end
end
