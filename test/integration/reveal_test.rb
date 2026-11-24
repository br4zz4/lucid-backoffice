require "integration_helper"

class RevealIntegrationTest < PanelTest
  REASON = "investigar chamado 123".freeze
  PATH = "/backoffice/tenants/alfa/data/students".freeze

  def setup
    super
    create_tenant_schemas
    @classification = write_yaml("students:\n  email: contact\n  cpf: documents\n")
    configure_tenants(permissions: { 1 => %i[browse view_tenant reveal view_activity], 2 => %i[browse view_tenant reveal] })
  end

  def configure_tenants(permissions:)
    classification = @classification
    configure_panel(permissions: permissions, tenancy: FakeTenancy.new) do |config|
      config.classification_path = classification
      yield config if block_given?
    end
  end

  def reveal(operator: 1, tenant: "alfa", reason: REASON, referer: PATH, **extra)
    post "/backoffice/reveals", params: { tenant_id: tenant, reason: reason }.merge(extra), headers: as(operator).merge("Referer" => referer)
  end

  def emails(path = PATH, operator: 1)
    get path, headers: as(operator)
    dom.css("thead th").map { |th| th.children.first.text.strip }.zip(dom.css("tbody tr").first.css("td").map { |td| td.text.strip }).to_h
  end

  def test_short_reason_shows_error_and_reveals_nothing
    # arrange
    short = "curto"

    # act
    reveal(reason: short)
    get(response.location, headers: as(1))

    # assert
    assert_includes dom.at_css(".lb-flash-error").text, "10"
    assert_equal 0, Lucid::Backoffice::Reveal.count
    assert_equal MASKED, emails["email"]
    assert_empty events("backoffice.reveal.grant")
  end

  def test_blank_reason_reveals_nothing
    # arrange
    blank = "   "

    # act
    reveal(reason: blank)

    # assert
    assert_equal 0, Lucid::Backoffice::Reveal.count
    assert_equal MASKED, emails["email"]
  end

  def test_category_param_is_ignored_even_when_unknown
    # arrange
    category = "nonexistent"

    # act
    reveal(category: category)
    get(response.location, headers: as(1))

    # assert
    assert_equal revealable_categories.sort, Lucid::Backoffice::Reveal.pluck(:category).sort
    assert dom.at_css(".lb-flash-ok")
    assert_nil dom.at_css(".lb-flash-error")
  end

  def test_valid_reason_reveals_every_allowed_category_in_clear_for_the_operator
    # arrange
    before = emails

    # act
    reveal
    get(response.location, headers: as(1))
    notice = dom.at_css(".lb-flash-ok")
    after = emails

    # assert
    assert notice
    assert_equal MASKED, before["email"]
    assert_equal SECRETS[:email], after["email"]
    assert_equal SECRETS[:cpf], after["cpf"]
    assert_equal SECRETS[:name], after["name"]
  end

  def test_posted_category_does_not_narrow_the_reveal
    # arrange
    reveal(category: "documents")

    # act
    row = emails

    # assert
    assert_equal SECRETS[:email], row["email"]
    assert_equal SECRETS[:cpf], row["cpf"]
    assert_equal revealable_categories.size, Lucid::Backoffice::Reveal.count
  end

  def test_reveal_is_scoped_to_the_tenant
    # arrange
    reveal(tenant: "alfa")

    # act
    alfa = emails("/backoffice/tenants/alfa/data/students")
    beta = emails("/backoffice/tenants/beta/data/students")
    insert_student(email: "shared@x.test")
    shared = emails("/backoffice/data/students")

    # assert
    assert_equal SECRETS[:email], alfa["email"]
    assert_equal MASKED, beta["email"]
    assert_equal MASKED, shared["email"]
  end

  def test_reveal_is_scoped_to_the_operator
    # arrange
    reveal(operator: 1)

    # act
    other = emails(operator: 2)
    owner = emails(operator: 1)

    # assert
    assert_equal MASKED, other["email"]
    assert_equal SECRETS[:email], owner["email"]
  end

  def test_reveal_expires_after_the_configured_duration
    # arrange
    reveal
    within = emails

    # act
    travel_to(Time.current + 16.minutes) { @after = emails }

    # assert
    assert_equal SECRETS[:email], within["email"]
    assert_equal MASKED, @after["email"]
  end

  def test_reveal_duration_is_configurable
    # arrange
    configure_tenants(permissions: { 1 => %i[browse view_tenant reveal] }) { |config| config.reveal_duration = 60 }
    reveal

    # act
    travel_to(Time.current + 2.minutes) { @after = emails }

    # assert
    assert_equal MASKED, @after["email"]
  end

  def test_delete_by_id_route_no_longer_exists
    # arrange
    reveal
    reveal_id = Lucid::Backoffice::Reveal.first.id

    # act
    status = begin
      delete "/backoffice/reveals/#{reveal_id}", headers: as(1)
      response.status
    rescue ActionController::RoutingError
      404
    end

    # assert
    assert_equal 404, status
    assert_equal revealable_categories.size, Lucid::Backoffice::Reveal.active.count
  end

  def test_grant_records_one_event_per_category_with_reason_and_tenant_without_values
    # arrange
    insert_student("alfa")

    # act
    reveal
    granted = events("backoffice.reveal.grant")
    contact = granted.find { |event| event.payload == { "category" => "contact" } }

    # assert
    assert_equal revealable_categories.sort, granted.map { |event| event.payload["category"] }.sort
    assert_equal [REASON], granted.map(&:reason).uniq
    assert_equal ["alfa"], granted.map(&:tenant_identifier).uniq
    assert_equal [1], granted.map(&:actor_id).uniq
    assert_equal "PanelOperator", contact.actor_type
    refute_includes granted.to_json, SECRETS[:email]
  end

  def test_tenant_page_offers_the_eye_form_with_disabled_submit_and_min_length
    # arrange
    path = "/backoffice/tenants/alfa"

    # act
    get path, headers: as(1)
    forms = dom.css("div.lb-reveal-dialog form[data-lb-reason-form]")

    # assert
    assert_response :ok
    assert_equal 1, forms.size
    assert_equal "/backoffice/reveals", forms.first["action"]
    assert_equal "10", forms.first.at_css("textarea[name=reason]")["minlength"]
    assert_equal "alfa", forms.first.at_css("input[name=tenant_id]")["value"]
    refute forms.first.at_css("[data-lb-submit]").key?("disabled")
    assert_empty forms.first.css("[name=category]")
  end

  def test_no_page_renders_the_per_category_reveal_list
    # arrange
    reveal
    paths = %w[/backoffice/data /backoffice/data/students /backoffice/tenants/alfa /backoffice/tenants/alfa/data /backoffice/tenants/alfa/data/students]

    # act
    found = paths.to_h do |path|
      get path, headers: as(1)
      [path, dom.css("section.lb-reveal, form.lb-reason-form").size]
    end

    # assert
    assert_equal paths.to_h { |path| [path, 0] }, found
  end

  def test_tenant_page_hides_the_eye_form_without_permission
    # arrange
    configure_tenants(permissions: { 1 => %i[view_tenant] })

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_response :ok
    assert_empty dom.css("div.lb-reveal-dialog")
    assert_empty dom.css("form[data-lb-reason-form]")
  end

  def test_single_tenant_reveal_is_per_operator
    # arrange
    classification = @classification
    configure_panel(permissions: { 1 => %i[browse reveal], 2 => %i[browse] }) { |config| config.classification_path = classification }
    insert_student

    # act
    post "/backoffice/reveals", params: { reason: REASON }, headers: as(1)
    mine = emails("/backoffice/data/students", operator: 1)
    theirs = emails("/backoffice/data/students", operator: 2)

    # assert
    assert_equal SECRETS[:email], mine["email"]
    assert_equal MASKED, theirs["email"]
  end

  def test_single_tenant_panel_offers_the_eye_form_to_operators_with_permission
    # arrange
    configure_panel(permissions: { 1 => %i[browse reveal] })
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_equal "/backoffice/reveals", dom.at_css("div.lb-reveal-dialog form[data-lb-reason-form]")&.[]("action")
  end

  def reveal_all(operator: 1, tenant: "alfa", reason: REASON, referer: PATH)
    params = { reason: reason }
    params[:tenant_id] = tenant if tenant
    post "/backoffice/reveals", params: params, headers: as(operator).merge("Referer" => referer)
  end

  def revoke_all(operator: 1, tenant: "alfa", referer: PATH)
    params = tenant ? { tenant_id: tenant } : {}
    delete "/backoffice/reveals", params: params, headers: as(operator).merge("Referer" => referer)
  end

  def revealable_categories = Lucid::Backoffice.configuration.categories - ["public"]

  def test_post_without_category_reveals_every_category_and_redirects_back_with_notice
    # arrange
    before = emails

    # act
    reveal_all
    status = response.status
    location = response.location
    get(location, headers: as(1))
    notice = dom.at_css(".lb-flash-ok")
    after = emails

    # assert
    assert_equal 302, status
    assert location.end_with?(PATH)
    assert notice
    assert_equal MASKED, before["email"]
    assert_equal SECRETS[:email], after["email"]
    assert_equal SECRETS[:cpf], after["cpf"]
    assert_equal revealable_categories.size, Lucid::Backoffice::Reveal.count
    assert_equal revealable_categories.size, events("backoffice.reveal.grant").size
    assert_equal [REASON], events("backoffice.reveal.grant").map(&:reason).uniq
    assert_equal ["alfa"], Lucid::Backoffice::Reveal.pluck(:tenant_identifier).uniq
  end

  def test_post_without_category_is_scoped_to_the_tenant
    # arrange
    reveal_all(tenant: "alfa")

    # act
    alfa = emails("/backoffice/tenants/alfa/data/students")
    beta = emails("/backoffice/tenants/beta/data/students")

    # assert
    assert_equal SECRETS[:email], alfa["email"]
    assert_equal MASKED, beta["email"]
  end

  def test_post_without_category_works_without_tenant
    # arrange
    configure_panel(permissions: { 1 => %i[browse reveal] }) { |config| config.classification_path = @classification }
    insert_student

    # act
    reveal_all(tenant: nil, referer: "/backoffice/data/students")
    row = emails("/backoffice/data/students")

    # assert
    assert_response :ok
    assert_equal SECRETS[:email], row["email"]
    assert_equal [nil], Lucid::Backoffice::Reveal.pluck(:tenant_identifier).uniq
  end

  def test_post_without_category_and_short_reason_alerts_and_creates_nothing
    # arrange
    short = "curto"

    # act
    reveal_all(reason: short)
    get(response.location, headers: as(1))

    # assert
    assert dom.at_css(".lb-flash-error")
    assert_equal 0, Lucid::Backoffice::Reveal.count
    assert_empty events("backoffice.reveal.grant")
    assert_equal MASKED, emails["email"]
  end

  def test_post_without_category_skips_denied_categories
    # arrange
    configure_tenants(permissions: {}) do |config|
      config.authorize = ->(_operator, _permission, context) { context[:category] != "documents" }
    end

    # act
    reveal_all
    row = emails

    # assert
    assert_equal SECRETS[:email], row["email"]
    assert_equal MASKED, row["cpf"]
    assert_equal revealable_categories.size - 1, Lucid::Backoffice::Reveal.count
    refute_includes Lucid::Backoffice::Reveal.pluck(:category), "documents"
  end

  def test_post_without_category_is_forbidden_when_every_category_is_denied
    # arrange
    configure_tenants(permissions: { 3 => %i[browse view_tenant] })

    # act
    reveal_all(operator: 3)

    # assert
    assert_response :forbidden
    assert_equal 0, Lucid::Backoffice::Reveal.count
    assert_empty events("backoffice.reveal.grant")
  end

  def test_post_with_category_still_reveals_every_category
    # arrange
    reveal(category: "contact")

    # act
    row = emails

    # assert
    assert_equal SECRETS[:email], row["email"]
    assert_equal SECRETS[:cpf], row["cpf"]
    assert_equal revealable_categories.size, Lucid::Backoffice::Reveal.count
  end

  def test_delete_collection_revokes_every_active_reveal_and_redirects_back
    # arrange
    reveal_all
    revealed = emails

    # act
    revoke_all
    status = response.status
    location = response.location
    after = emails

    # assert
    assert_equal 302, status
    assert location.end_with?(PATH)
    assert_equal SECRETS[:email], revealed["email"]
    assert_equal MASKED, after["email"]
    assert_equal MASKED, after["cpf"]
    assert_equal revealable_categories.size, events("backoffice.reveal.revoke").size
  end

  def test_delete_collection_does_not_touch_another_tenant
    # arrange
    reveal_all(tenant: "alfa")
    reveal_all(tenant: "beta", referer: "/backoffice/tenants/beta/data/students")

    # act
    revoke_all(tenant: "alfa")

    # assert
    assert_equal MASKED, emails("/backoffice/tenants/alfa/data/students")["email"]
    assert_equal SECRETS[:email], emails("/backoffice/tenants/beta/data/students")["email"]
  end

  def test_delete_collection_does_not_touch_another_operator
    # arrange
    reveal_all(operator: 1)
    reveal_all(operator: 2)

    # act
    revoke_all(operator: 1)

    # assert
    assert_equal MASKED, emails(operator: 1)["email"]
    assert_equal SECRETS[:email], emails(operator: 2)["email"]
  end

  def test_delete_collection_by_an_operator_without_reveals_leaves_others_untouched
    # arrange
    reveal_all
    configure_tenants(permissions: { 1 => %i[browse view_tenant reveal], 3 => %i[browse view_tenant] })

    # act
    revoke_all(operator: 3)

    # assert
    assert_equal 0, events("backoffice.reveal.revoke").size
    assert_equal SECRETS[:email], emails(operator: 1)["email"]
  end

  def test_revealed_values_still_hide_secret_columns
    # arrange
    reveal

    # act
    get PATH, headers: as(1)

    # assert
    assert_includes response.body, SECRETS[:email]
    %i[password_digest api_token otp_secret encrypted_phone].each { |column| refute_includes response.body, SECRETS[column] }
  end

  def test_delete_collection_ends_the_reveals_even_when_authorize_now_denies_reveal
    # arrange
    reveal_all
    configure_tenants(permissions: {}) { |config| config.authorize = ->(_operator, permission, _context) { permission != :reveal } }

    # act
    revoke_all

    # assert
    assert_equal 302, response.status
    assert_equal 0, Lucid::Backoffice::Reveal.active.count
    assert_equal revealable_categories.size, events("backoffice.reveal.revoke").size
  end

  def test_delete_collection_ends_the_reveals_when_authorize_compares_the_tenant_object
    # arrange
    reveal_all
    configure_tenants(permissions: {}) do |config|
      config.authorize = ->(_operator, permission, context) { permission == :reveal ? context[:tenant]&.code == "never" : true }
    end

    # act
    revoke_all

    # assert
    assert_equal 0, Lucid::Backoffice::Reveal.active.count
  end

  def test_delete_collection_without_reveal_permission_leaves_other_operators_and_tenants
    # arrange
    reveal_all(operator: 1, tenant: "alfa")
    reveal_all(operator: 1, tenant: "beta", referer: "/backoffice/tenants/beta/data/students")
    reveal_all(operator: 2, tenant: "alfa")
    configure_tenants(permissions: {}) { |config| config.authorize = ->(_operator, permission, _context) { permission != :reveal } }

    # act
    revoke_all(operator: 1, tenant: "alfa")

    # assert
    active = Lucid::Backoffice::Reveal.active.pluck(:operator_id, :tenant_identifier).tally
    assert_equal({ [1, "beta"] => revealable_categories.size, [2, "alfa"] => revealable_categories.size }, active)
  end
end
