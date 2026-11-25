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
end
