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

  def reveal(operator: 1, tenant: "alfa", category: "contact", reason: REASON, referer: PATH)
    post "/backoffice/reveals", params: { tenant_id: tenant, category: category, reason: reason }, headers: as(operator).merge("Referer" => referer)
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

  def test_unknown_category_reveals_nothing
    # arrange
    category = "nonexistent"

    # act
    reveal(category: category)
    get(response.location, headers: as(1))

    # assert
    assert_equal 0, Lucid::Backoffice::Reveal.count
    assert dom.at_css(".lb-flash-error")
  end

  def test_valid_reason_reveals_category_in_clear_for_the_operator
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
    assert_equal MASKED, after["cpf"]
    assert_equal MASKED, after["name"]
  end

  def test_only_the_requested_category_is_revealed
    # arrange
    reveal(category: "documents")

    # act
    row = emails

    # assert
    assert_equal MASKED, row["email"]
    assert_equal SECRETS[:cpf], row["cpf"]
    assert_equal MASKED, row["name"]
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

  def test_delete_ends_the_reveal_on_the_next_request
    # arrange
    reveal
    reveal_id = Lucid::Backoffice::Reveal.sole.id
    revealed = emails

    # act
    delete "/backoffice/reveals/#{reveal_id}", headers: as(1).merge("Referer" => PATH)
    after = emails

    # assert
    assert_equal SECRETS[:email], revealed["email"]
    assert_response :ok
    assert_equal MASKED, after["email"]
    assert_equal 1, events("backoffice.reveal.revoke").size
  end

  def test_other_operator_cannot_end_a_reveal_without_permission
    # arrange
    reveal
    reveal_id = Lucid::Backoffice::Reveal.sole.id
    configure_tenants(permissions: { 1 => %i[browse view_tenant reveal], 3 => %i[browse] })

    # act
    delete "/backoffice/reveals/#{reveal_id}", headers: as(3)

    # assert
    assert_response :forbidden
    assert_nil Lucid::Backoffice::Reveal.sole.revoked_at
  end

  def test_grant_records_event_with_reason_category_and_tenant_without_values
    # arrange
    insert_student("alfa")

    # act
    reveal
    event = events("backoffice.reveal.grant").sole

    # assert
    assert_equal REASON, event.reason
    assert_equal({ "category" => "contact" }, event.payload)
    assert_equal "alfa", event.tenant_identifier
    assert_equal 1, event.actor_id
    assert_equal "PanelOperator", event.actor_type
    refute_includes event.to_json, SECRETS[:email]
  end

  def test_tenant_page_offers_reveal_form_with_disabled_submit_and_min_length
    # arrange
    path = "/backoffice/tenants/alfa"

    # act
    get path, headers: as(1)
    forms = dom.css("form.lb-reason-form")

    # assert
    assert_response :ok
    assert_equal 6, forms.size
    assert_equal "/backoffice/reveals", forms.first["action"]
    assert_equal "10", forms.first.at_css("input[name=reason]")["minlength"]
    assert_equal "alfa", forms.first.at_css("input[name=tenant_id]")["value"]
    assert forms.first.at_css("input[type=submit][disabled]")
  end

  def test_tenant_page_offers_end_button_for_active_reveal
    # arrange
    reveal

    # act
    get "/backoffice/tenants/alfa", headers: as(1)
    buttons = dom.css("section.lb-reveal form.button_to[method=post] input[name=_method][value=delete]")

    # assert
    assert_equal 1, buttons.size
    assert_equal 5, dom.css("form.lb-reason-form").size
  end

  def test_tenant_page_hides_reveal_form_without_permission
    # arrange
    configure_tenants(permissions: { 1 => %i[view_tenant] })

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    assert_response :ok
    assert_empty dom.css("form.lb-reason-form")
  end

  def test_single_tenant_reveal_is_per_operator_and_category
    # arrange
    classification = @classification
    configure_panel(permissions: { 1 => %i[browse reveal], 2 => %i[browse] }) { |config| config.classification_path = classification }
    insert_student

    # act
    post "/backoffice/reveals", params: { category: "contact", reason: REASON }, headers: as(1)
    mine = emails("/backoffice/data/students", operator: 1)
    theirs = emails("/backoffice/data/students", operator: 2)

    # assert
    assert_equal SECRETS[:email], mine["email"]
    assert_equal MASKED, theirs["email"]
  end

  def test_single_tenant_panel_offers_a_reveal_form_to_operators_with_permission
    # arrange
    configure_panel(permissions: { 1 => %i[browse reveal] })
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_equal "/backoffice/reveals", dom.at_css("form.lb-reason-form")&.[]("action")
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

  def test_post_with_category_keeps_revealing_only_that_category
    # arrange
    reveal(category: "contact")

    # act
    row = emails

    # assert
    assert_equal SECRETS[:email], row["email"]
    assert_equal MASKED, row["cpf"]
    assert_equal 1, Lucid::Backoffice::Reveal.count
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
    %w[contact documents minors financial free_text unclassified].each { |category| reveal(category: category) }

    # act
    get PATH, headers: as(1)

    # assert
    assert_includes response.body, SECRETS[:email]
    %i[password_digest api_token otp_secret encrypted_phone].each { |column| refute_includes response.body, SECRETS[column] }
  end
end
