require "integration_helper"
require "action_helper"

class FieldUnlockIntegrationTest < PanelTest
  ACTIONS = "/backoffice/actions".freeze
  REASON = "corrigir cadastro 4521".freeze
  CURRENT = "teacher-ATUAL-77".freeze
  NEW_VALUE = "coordinator-NOVO-88".freeze
  SECRET = "SEGREDO-ATUAL-55".freeze
  PERMISSIONS = {
    1 => %i[run_action reveal browse view_dashboard view_tenant],
    2 => %i[run_action browse view_dashboard view_tenant],
    3 => %i[reveal browse view_dashboard view_tenant]
  }.freeze
  CLASSIFICATION = <<~YAML.freeze
    accounts:
      role: contact
      nickname: public
      level: public
    gadgets:
      name: public
      kind: public
      secret_code: contact
  YAML

  def setup
    super
    Lucid::Backoffice::Action.reset!
    Lucid::Backoffice::Resource.reset!
    Account.delete_all
    Gadget.delete_all
  end

  def teardown
    Lucid::Backoffice::Action.reset!
    Lucid::Backoffice::Resource.reset!
    Account.delete_all
    Gadget.delete_all
    super
  end

  def configure_unlock
    path = write_yaml(CLASSIFICATION)
    configure_panel(permissions: PERMISSIONS) { |config| config.classification_path = path }
  end

  def define_action(name, &body)
    klass = Class.new(Lucid::Backoffice::Action)
    klass.define_singleton_method(:name) { name }
    klass.class_eval(&body)
    klass
  end

  def edit_accounts
    define_action("EditAccounts") do
      on :accounts
      field :role, :string
      field :nickname, :string
      perform { record.update!(role: role, nickname: nickname) }
    end
  end

  def edit_gadgets
    define_action("EditGadgets") do
      on :gadgets
      field :name, :string, required: false
      field :secret_code, :string, required: false
      field :kind, :string, required: false
      perform { record.update!(name: name, secret_code: secret_code, kind: kind) }
    end
  end

  def create_account(**attributes)
    Account.create!({ role: CURRENT, nickname: "Mia", level: 1 }.merge(attributes))
  end

  def create_gadget
    Gadget.create!(name: "Torno", kind: "oculto-9", secret_code: SECRET)
  end

  def grant_contact_reveal
    Lucid::Backoffice::Reveal.create!(operator_type: "PanelOperator", operator_id: 1, tenant_identifier: Lucid::Backoffice::Reveal.tenant_identifier(nil),
                                      category: "contact", reason: REASON, expires_at: 1.hour.from_now)
  end

  def snapshot_value = dom.at_css("input[name=snapshot]")&.[]("value")
  def locked_wrapper(field) = dom.at_css(".lb-field:has(label[for=fields_#{field}]) .lb-locked-field")
  def live_controls(field) = dom.css("[name='fields[#{field}]']").reject { |node| node.ancestors("template").any? }
  def unlock_url(field) = locked_wrapper(field)&.then { |node| node["data-lb-unlock-url"] || node.at_css("[data-lb-unlock-url]")&.[]("data-lb-unlock-url") }
  def unlock_button(field) = locked_wrapper(field)&.at_css("button")
  def unlock_path(key, field) = "#{ACTIONS}/#{key}/fields/#{field}/unlock"
  def unlock_events = events("backoffice.field.unlock")

  def open_form(key, record, fields: nil, unlocked: nil, operator: 1)
    params = { record_id: record.id }
    params[:fields] = fields if fields
    params[:unlocked] = unlocked if unlocked
    get "#{ACTIONS}/#{key}/new", params: params, headers: as(operator)
  end

  def unlock(key, record, field, operator: 1)
    post unlock_path(key, field), params: { record_id: record.id }, headers: as(operator).merge("Accept" => "application/json")
  end

  def run_with(key, record, fields:, unlocked: nil, operator: 1)
    open_form(key, record, fields: fields, unlocked: unlocked, operator: operator)
    snapshot = snapshot_value
    params = { record_id: record.id, fields: fields, snapshot: snapshot, reason: REASON }
    params[:unlocked] = unlocked if unlocked
    post "#{ACTIONS}/#{key}", params: params, headers: as(operator)
  end

  def preview(key, record, fields: nil, unlocked: nil, operator: 1)
    params = { record_id: record.id }
    params[:fields] = fields if fields
    params[:unlocked] = unlocked if unlocked
    post "#{ACTIONS}/#{key}/preview", params: params, headers: as(operator)
  end

  def action_form = dom.at_css("form.lb-action-form")

  def form_pairs
    nodes = action_form.css("input, textarea, select").reject { |node| node.ancestors("template").any? || node["disabled"] }
    nodes.filter_map do |node|
      name = node["name"]
      type = node["type"].to_s.downcase
      next if name.to_s.empty? || %w[submit button image].include?(type)
      next if name == "tenant_id" && node["value"].to_s.empty?
      next if %w[checkbox radio].include?(type) && !node.key?("checked")

      value = if node.name == "select"
        (node.at_css("option[selected]") || node.at_css("option"))&.[]("value").to_s
      elsif node.name == "textarea"
        node.text
      else
        node["value"].to_s
      end
      [name, value]
    end
  end

  def run_from_dom(key, pairs)
    body = URI.encode_www_form(pairs + [["reason", REASON]])
    post "#{ACTIONS}/#{key}", params: body, headers: as(1)
  end

  def closed_wrapper(field) = dom.at_css(".lb-field:has(label[for=fields_#{field}]) .lb-locked-field:not([data-lb-unlock-open])")

  def open_wrapper(field) = dom.at_css("div.lb-locked-field[data-lb-unlock-open]:has([name='fields[#{field}]'])")

  def rejected_by_forgery_protection
    post_status = nil
    begin
      yield
      post_status = response.status
    rescue ActionController::InvalidAuthenticityToken
      post_status = 422
    end
    post_status
  end

  def swapping_activity_record(replacement)
    original = Lucid::Backoffice::Activity.method(:record)
    Lucid::Backoffice::Activity.define_singleton_method(:record, &replacement)
    yield
  ensure
    Lucid::Backoffice::Activity.define_singleton_method(:record, original)
  end

  def test_locked_field_stays_locked_with_the_category_revealed_and_leaks_nothing
    # arrange
    configure_unlock
    edit_accounts
    account = create_account
    grant_contact_reveal

    # act
    open_form("edit_accounts", account)

    # assert
    assert_response :ok
    wrapper = locked_wrapper("role")
    input = wrapper.at_css("input")
    assert_equal "read", wrapper["data-lb-unlock"]
    assert_equal [MASKED, "disabled", nil], [input["value"], input["disabled"], input["name"]]
    assert_empty live_controls("role")
    assert_includes wrapper.at_css("template").to_s, "fields[role]"
    refute_includes response.body, CURRENT
    assert_equal I18n.t("lucid_backoffice.unlock_field"), unlock_button("role").text.strip
  end

  def test_unlock_button_points_to_the_unlock_endpoint
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    open_form("edit_accounts", account)

    # assert
    url = unlock_url("role")
    assert_includes url, "/backoffice/actions/edit_accounts/fields/role/unlock"
    assert_includes url, "record_id=#{account.id}"
  end

  def test_public_field_is_not_locked
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    open_form("edit_accounts", account)

    # assert
    assert_nil locked_wrapper("nickname")
    assert_equal "Mia", dom.at_css("input[name='fields[nickname]']")["value"]
  end

  def test_unlock_returns_the_value_with_no_store_and_records_an_event_without_value_or_reason
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    unlock("edit_accounts", account, "role")

    # assert
    assert_response :ok
    assert_equal({ "value" => CURRENT }, JSON.parse(response.body))
    assert_includes response.headers["Cache-Control"], "no-store"
    event = unlock_events.sole
    assert_equal [{ "type" => "Table", "name" => "accounts", "id" => account.id }], event.subjects
    assert_equal({ "column" => "role", "action" => "edit_accounts" }, event.payload)
    assert_nil event.reason
    refute_includes event.to_json, CURRENT
  end

  def test_unlock_works_with_the_category_not_revealed_and_with_it_revealed
    # arrange
    configure_unlock
    edit_accounts
    account = create_account
    grant_contact_reveal

    # act
    unlock("edit_accounts", account, "role")

    # assert
    assert_response :ok
    assert_equal CURRENT, JSON.parse(response.body)["value"]
    assert_equal 1, unlock_events.size
  end

  def test_unlock_without_reveal_permission_is_403_without_value_or_event
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    unlock("edit_accounts", account, "role", operator: 2)

    # assert
    assert_response :forbidden
    refute_includes response.body, CURRENT
    assert_empty unlock_events
  end

  def test_unlock_without_the_action_permission_is_403_without_value_or_event
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    unlock("edit_accounts", account, "role", operator: 3)

    # assert
    assert_response :forbidden
    refute_includes response.body, CURRENT
    assert_empty unlock_events
  end

  def test_form_without_reveal_permission_has_no_unlock_button
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    open_form("edit_accounts", account, operator: 2)

    # assert
    assert_response :ok
    wrapper = locked_wrapper("role")
    assert_equal [MASKED, nil], [wrapper.at_css("input")["value"], wrapper.at_css("input")["name"]]
    assert_nil wrapper.at_css("button")
    refute_includes response.body, CURRENT
  end

  def test_secret_column_is_write_only
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget

    # act
    open_form("edit_gadgets", gadget)

    # assert
    wrapper = locked_wrapper("secret_code")
    assert_equal "write", wrapper["data-lb-unlock"]
    assert_nil unlock_url("secret_code")
    assert_nil wrapper.at_css("input")["name"]
    assert_equal I18n.t("lucid_backoffice.set_new_value"), unlock_button("secret_code").text.strip
    refute_includes response.body, SECRET
  end

  def test_secret_column_unlock_endpoint_is_403_without_value_or_event
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget

    # act
    unlock("edit_gadgets", gadget, "secret_code")

    # assert
    assert_response :forbidden
    refute_includes response.body, SECRET
    assert_empty unlock_events
  end

  def test_resource_hidden_column_is_write_only_and_endpoint_is_403
    # arrange
    configure_unlock
    Class.new(Lucid::Backoffice::Resource) do
      table :gadgets
      hide :kind
    end
    edit_gadgets
    gadget = create_gadget

    # act
    open_form("edit_gadgets", gadget)
    wrapper = locked_wrapper("kind")
    label = unlock_button("kind").text.strip
    unlock("edit_gadgets", gadget, "kind")

    # assert
    assert_equal ["write", I18n.t("lucid_backoffice.set_new_value")], [wrapper["data-lb-unlock"], label]
    assert_response :forbidden
    refute_includes response.body, "oculto-9"
    assert_empty unlock_events
  end

  def test_unlock_of_a_public_field_is_404
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    unlock("edit_accounts", account, "nickname")

    # assert
    assert_response :not_found
    refute_includes response.body, "Mia"
    assert_empty unlock_events
  end

  def test_unlock_of_an_unknown_field_is_404
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    unlock("edit_accounts", account, "missing")

    # assert
    assert_response :not_found
    assert_empty unlock_events
  end

  def test_saving_an_unlocked_field_updates_the_record_and_records_only_the_field_name
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    run_with("edit_accounts", account, fields: { role: NEW_VALUE, nickname: "Mia" }, unlocked: %w[role])

    # assert
    assert_response :redirect
    assert_equal NEW_VALUE, account.reload.role
    event = events("backoffice.action.edit_accounts").sole
    assert_includes event.changed_fields, "role"
    assert_equal REASON, event.reason
    refute_includes event.to_json, NEW_VALUE
    refute_includes event.to_json, CURRENT
  end

  def test_forged_value_without_unlocked_is_discarded
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    run_with("edit_accounts", account, fields: { role: "hacked", nickname: "Zoe" })

    # assert
    assert_equal [CURRENT, "Zoe"], account.reload.then { |a| [a.role, a.nickname] }
  end

  def test_forged_value_is_discarded_even_with_the_category_revealed
    # arrange
    configure_unlock
    edit_accounts
    account = create_account
    grant_contact_reveal

    # act
    run_with("edit_accounts", account, fields: { role: "hacked", nickname: "Zoe" })

    # assert
    assert_equal [CURRENT, "Zoe"], account.reload.then { |a| [a.role, a.nickname] }
  end

  def test_unlocked_without_reveal_permission_is_discarded
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    run_with("edit_accounts", account, fields: { role: "hacked", nickname: "Zoe" }, unlocked: %w[role], operator: 2)

    # assert
    assert_equal [CURRENT, "Zoe"], account.reload.then { |a| [a.role, a.nickname] }
  end

  def test_unlocked_only_applies_to_the_named_field
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget

    # act
    run_with("edit_gadgets", gadget, fields: { name: "Novo", secret_code: "INVADIDO", kind: "k2" }, unlocked: %w[kind])

    # assert
    assert_equal ["Novo", SECRET], gadget.reload.then { |g| [g.name, g.secret_code] }
  end

  def test_secret_unlocked_with_a_new_value_is_written
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget

    # act
    run_with("edit_gadgets", gadget, fields: { name: "Torno", secret_code: "NOVO-SEGREDO-1", kind: "k2" }, unlocked: %w[secret_code])

    # assert
    assert_equal "NOVO-SEGREDO-1", gadget.reload.secret_code
    event = events("backoffice.action.edit_gadgets").sole
    assert_includes event.changed_fields, "secret_code"
    refute_includes event.to_json, "NOVO-SEGREDO-1"
  end

  def test_secret_unlocked_and_left_blank_keeps_the_current_value
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget

    # act
    run_with("edit_gadgets", gadget, fields: { name: "Torno", secret_code: "", kind: "k2" }, unlocked: %w[secret_code])

    # assert
    assert_equal SECRET, gadget.reload.secret_code
  end

  def test_secret_forged_without_unlocked_is_discarded
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget

    # act
    run_with("edit_gadgets", gadget, fields: { name: "Torno", secret_code: "INVADIDO", kind: "k2" })

    # assert
    assert_equal SECRET, gadget.reload.secret_code
  end

  def test_without_javascript_the_locked_field_has_no_name_and_the_action_runs_with_current_values
    # arrange
    configure_unlock
    edit_accounts
    account = create_account
    open_form("edit_accounts", account)
    names = dom.css("form input, form select, form textarea").reject { |node| node.ancestors("template").any? }.filter_map { |node| node["name"] }

    # act
    run_with("edit_accounts", account, fields: { nickname: "Zoe" })

    # assert
    refute_includes names, "fields[role]"
    assert_includes names, "fields[nickname]"
    assert_response :redirect
    assert_equal [CURRENT, "Zoe"], account.reload.then { |a| [a.role, a.nickname] }
  end

  def test_preview_post_returns_the_unlocked_field_open_with_the_sent_value
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    preview("edit_accounts", account, fields: { role: NEW_VALUE, nickname: "Mia" }, unlocked: %w[role])

    # assert
    assert_response :ok
    wrapper = open_wrapper("role")
    assert wrapper
    assert_equal NEW_VALUE, wrapper.at_css("[name='fields[role]']")["value"]
    assert_equal "role", wrapper.at_css("input[type=hidden][name='unlocked[]']")["value"]
    assert wrapper.at_css("[data-lb-unlock-button]")
    assert_nil closed_wrapper("role")
    assert_empty dom.css("input[disabled].lb-locked").select { |node| node.ancestors(".lb-field").any? { |field| field.at_css("label[for=fields_role]") } }
  end

  def test_preview_post_keeps_a_not_accepted_field_locked
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    preview("edit_accounts", account, fields: { role: "hacked", nickname: "Mia" }, unlocked: %w[role], operator: 2)

    # assert
    assert_response :ok
    assert_nil open_wrapper("role")
    assert closed_wrapper("role")
    assert_empty live_controls("role")
    refute_includes response.body, "hacked"
  end

  def test_preview_post_keeps_a_secret_field_locked_when_unlocked_with_a_blank_value
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget

    # act
    preview("edit_gadgets", gadget, fields: { name: "Torno", secret_code: "", kind: "oculto-9" }, unlocked: %w[secret_code])

    # assert
    assert_response :ok
    assert_nil open_wrapper("secret_code")
    assert closed_wrapper("secret_code")
  end

  def test_preview_post_returns_a_secret_field_open_with_the_new_value
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget

    # act
    preview("edit_gadgets", gadget, fields: { name: "Torno", secret_code: "NOVO-SEGREDO-1", kind: "oculto-9" }, unlocked: %w[secret_code])

    # assert
    wrapper = open_wrapper("secret_code")
    assert wrapper
    assert_equal "NOVO-SEGREDO-1", wrapper.at_css("[name='fields[secret_code]']")["value"]
    assert_nil closed_wrapper("secret_code")
    refute_includes response.body, SECRET
  end

  def test_unlocked_field_survives_preview_and_execution_through_the_dom
    # arrange
    configure_unlock
    edit_accounts
    account = create_account
    preview("edit_accounts", account, fields: { role: NEW_VALUE, nickname: "Mia" }, unlocked: %w[role])

    # act
    pairs = form_pairs
    run_from_dom("edit_accounts", pairs)

    # assert
    assert_includes pairs.map(&:first), "snapshot"
    assert_includes pairs, ["unlocked[]", "role"]
    assert_includes pairs, ["fields[role]", NEW_VALUE]
    assert_response :redirect
    assert_equal NEW_VALUE, account.reload.role
    assert_equal 1, events("backoffice.action.edit_accounts").size
  end

  def test_secret_field_survives_preview_and_execution_through_the_dom
    # arrange
    configure_unlock
    edit_gadgets
    gadget = create_gadget
    preview("edit_gadgets", gadget, fields: { name: "Torno", secret_code: "NOVO-SEGREDO-1", kind: "oculto-9" }, unlocked: %w[secret_code])

    # act
    pairs = form_pairs
    run_from_dom("edit_gadgets", pairs)

    # assert
    assert_includes pairs, ["unlocked[]", "secret_code"]
    assert_response :redirect
    assert_equal "NOVO-SEGREDO-1", gadget.reload.secret_code
  end

  def test_action_form_posts_to_the_preview_endpoint_without_values_in_the_url
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    open_form("edit_accounts", account)

    # assert
    assert_equal "post", action_form["method"].downcase
    assert action_form["action"].end_with?("/actions/edit_accounts/preview")
    refute_includes action_form["action"], "?"
    assert_empty action_form.css("input[name=authenticity_token]")
  end

  def test_action_form_has_a_single_native_authenticity_token_when_forgery_protection_is_on
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    with_forgery_protection { open_form("edit_accounts", account) }

    # assert
    assert_equal 1, action_form.css("input[name=authenticity_token]").size
  end

  def test_get_new_with_a_locked_field_exposes_no_value_in_the_html
    # arrange
    configure_unlock
    edit_accounts
    edit_gadgets
    account = create_account
    gadget = create_gadget
    grant_contact_reveal

    # act
    open_form("edit_accounts", account)
    account_body = response.body
    open_form("edit_gadgets", gadget)

    # assert
    refute_includes account_body, CURRENT
    refute_includes response.body, SECRET
  end

  def test_unlock_without_a_csrf_token_is_rejected_without_value_or_event
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    status = with_forgery_protection { rejected_by_forgery_protection { unlock("edit_accounts", account, "role") } }

    # assert
    assert_equal 422, status
    assert_empty unlock_events
  end

  def test_unlock_with_a_valid_csrf_token_returns_the_value
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    with_forgery_protection do
      open_form("edit_accounts", account)
      token = csrf_token
      post unlock_path("edit_accounts", "role"), params: { record_id: account.id },
                                                 headers: as(1).merge("Accept" => "application/json", "X-CSRF-Token" => token)
    end

    # assert
    assert_response :ok
    assert_equal CURRENT, JSON.parse(response.body)["value"]
    assert_equal 1, unlock_events.size
  end

  def test_preview_post_without_a_csrf_token_is_rejected
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    status = with_forgery_protection { rejected_by_forgery_protection { preview("edit_accounts", account, fields: { nickname: "Mia" }) } }

    # assert
    assert_equal 422, status
  end

  def test_preview_post_with_the_form_token_is_accepted
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    with_forgery_protection do
      open_form("edit_accounts", account)
      token = action_form.at_css("input[name=authenticity_token]")["value"]
      post "#{ACTIONS}/edit_accounts/preview", params: { record_id: account.id, fields: { nickname: "Mia" }, authenticity_token: token }, headers: as(1)
    end

    # assert
    assert_response :ok
    assert action_form
  end

  def test_empty_tenant_id_is_treated_as_no_tenant_on_new_preview_and_run
    # arrange
    configure_unlock
    edit_accounts
    account = create_account

    # act
    get "#{ACTIONS}/edit_accounts/new", params: { record_id: account.id, tenant_id: "" }, headers: as(1)
    new_status = response.status
    post "#{ACTIONS}/edit_accounts/preview", params: { record_id: account.id, tenant_id: "", fields: { nickname: "Zoe" } }, headers: as(1)
    preview_status = response.status
    snapshot = snapshot_value
    post "#{ACTIONS}/edit_accounts", params: { record_id: account.id, tenant_id: "", fields: { nickname: "Zoe" }, snapshot: snapshot, reason: REASON }, headers: as(1)

    # assert
    assert_equal 200, new_status
    assert_equal 200, preview_status
    assert_response :redirect
    assert_equal "Zoe", account.reload.nickname
  end

  def test_unlock_fails_closed_when_the_event_cannot_be_recorded
    # arrange
    configure_unlock
    edit_accounts
    account = create_account
    failing = proc { |**| raise ActiveRecord::StatementInvalid, "boom" }
    body = nil

    # act
    swapping_activity_record(failing) do
      begin
        unlock("edit_accounts", account, "role")
        body = response.body
      rescue ActiveRecord::StatementInvalid
        body = ""
      end
    end

    # assert
    refute_includes body, CURRENT
    refute_equal 200, response.status unless body.empty?
    assert_empty unlock_events
  end
end
