require "integration_helper"
require "action_helper"

class ActionTenancy < FakeTenancy
  def self.log = (@log ||= [])

  def with(tenant)
    self.class.log << "enter #{tenant&.code}"
    yield
  ensure
    self.class.log << "exit #{tenant&.code}"
  end
end

class ActionsIntegrationTest < PanelTest
  ACTIONS = "/backoffice/actions".freeze
  REASON = "investigar chamado 123".freeze
  OPERATOR = { 1 => %i[run_action browse view_dashboard view_tenant], 2 => %i[browse view_dashboard view_tenant] }.freeze
  DEFAULT_CATEGORY_REVEAL = "contact".freeze

  def setup
    super
    Lucid::Backoffice::Action.reset!
    Account.delete_all
    ActionTenancy.log.clear
  end

  def teardown
    Lucid::Backoffice::Action.reset!
    Account.delete_all
    super
  end

  def configure_actions(permissions: OPERATOR, tenancy: nil)
    path = write_yaml(ActionTest::CLASSIFICATION)
    configure_panel(permissions: permissions, tenancy: tenancy) { |config| config.classification_path = path }
  end

  def define_action(name = "ChangeUserRole", &body)
    klass = Class.new(Lucid::Backoffice::Action)
    klass.define_singleton_method(:name) { name }
    klass.class_eval(&body)
    klass
  end

  def role_action(name = "ChangeUserRole", &extra)
    define_action(name) do
      on :accounts
      label "Corrigir papel"
      field :role, :select, choices: -> { %w[teacher coordinator director] }
      perform { record.update!(role: role) }
      class_eval(&extra) if extra
    end
  end

  def create_account(**attributes)
    Account.create!({ role: "teacher", nickname: "Mia", level: 1 }.merge(attributes))
  end

  def snapshot_value = dom.at_css("input[name=snapshot]")&.[]("value")
  def alert_text = dom.at_css(".lb-flash-error")&.text.to_s
  def preview_section = dom.at_css("section.lb-section")
  def execute_button = dom.at_css("input[type=submit][data-lb-submit]")

  def open_preview(key, params, operator: 1)
    get "#{ACTIONS}/#{key}/new", params: params, headers: as(operator)
  end

  def submit_action(key, params, operator: 1)
    post "#{ACTIONS}/#{key}", params: params, headers: as(operator)
  end

  def role_preview(account, role: "coordinator", key: "change_user_role")
    open_preview(key, { record_id: account.id, fields: { role: role } })
    snapshot_value
  end

  def role_submission(account, snapshot, role: "coordinator", **overrides)
    { record_id: account.id, fields: { role: role }, snapshot: snapshot, reason: REASON }.merge(overrides)
  end

  def action_events = events("backoffice.action.change_user_role")

  def grant_contact_reveal
    Lucid::Backoffice::Reveal.create!(operator_type: "PanelOperator", operator_id: 1, tenant_identifier: Lucid::Backoffice::Reveal.tenant_identifier(nil),
                                      category: DEFAULT_CATEGORY_REVEAL, reason: REASON, expires_at: 1.hour.from_now)
  end

  def valid_field_values
    { title: "t", body: "b", qty: "5", flag: "1", due: "2026-01-02", kind: "x", owner: "3", custom: "c" }
  end

  def everything_action
    define_action("Everything") do
      on :global
      field :title, :string
      field :body, :text
      field :qty, :integer
      field :flag, :boolean, required: false
      field :due, :date
      field :kind, :select, choices: -> { Account.order(:id).pluck(:role) }
      field :owner, :record, of: :accounts
      field :custom, :string, partial: "test_fields/custom"
      perform { nil }
    end
  end

  def test_new_shows_the_field_filled_with_the_current_value
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")

    # act
    open_preview("change_user_role", { record_id: account.id })

    # assert
    assert_response :ok
    assert_equal "teacher", dom.at_css("select[name='fields[role]'] option[selected]")["value"]
  end

  def test_new_shows_no_preview_until_values_are_submitted
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")

    # act
    open_preview("change_user_role", { record_id: account.id })

    # assert
    assert_nil snapshot_value
    assert_nil preview_section
    assert_nil execute_button
  end

  def test_new_with_values_shows_the_masked_preview
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")

    # act
    open_preview("change_user_role", { record_id: account.id, fields: { role: "coordinator" } })

    # assert
    assert_response :ok
    text = preview_section.text
    assert_includes text, MASKED
    refute_includes text, "teacher"
    refute_includes text, "coordinator"
  end

  def test_new_with_values_reveals_the_preview_when_the_category_was_revealed
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")
    grant_contact_reveal

    # act
    open_preview("change_user_role", { record_id: account.id, fields: { role: "coordinator" } })

    # assert
    assert_includes preview_section.text, "teacher"
    assert_includes preview_section.text, "coordinator"
  end

  def test_new_with_values_carries_the_snapshot_in_a_hidden_field
    # arrange
    configure_actions
    role_action
    account = create_account

    # act
    open_preview("change_user_role", { record_id: account.id, fields: { role: "coordinator" } })

    # assert
    assert_match(/\A\h{64}\z/, snapshot_value)
    assert_equal "hidden", dom.at_css("input[name=snapshot]")["type"]
  end

  def test_new_with_values_renders_execute_disabled_until_a_reason
    # arrange
    configure_actions
    role_action
    account = create_account

    # act
    open_preview("change_user_role", { record_id: account.id, fields: { role: "coordinator" } })

    # assert
    assert_equal "disabled", execute_button["disabled"]
    reason = dom.at_css("input[name=reason]")
    assert_equal ["required", Lucid::Backoffice.configuration.reveal_reason_min.to_s], [reason["required"], reason["minlength"]]
  end

  def test_post_without_or_with_short_reason_is_rejected_and_writes_nothing
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")
    snapshot = role_preview(account)

    # act
    statuses = ["", "curto"].map do |reason|
      submit_action("change_user_role", role_submission(account, snapshot, reason: reason))
      [response.status, alert_text.include?("reason")]
    end

    # assert
    assert_equal [[422, true]] * 2, statuses
    assert_equal "teacher", account.reload.role
    assert_empty action_events
  end

  def test_post_with_reason_and_matching_snapshot_writes_and_records_the_event
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")
    snapshot = role_preview(account)

    # act
    submit_action("change_user_role", role_submission(account, snapshot))

    # assert
    assert_response :redirect
    assert_equal "coordinator", account.reload.role
    event = action_events.sole
    assert_equal ["ok", REASON, "PanelOperator", 1], [event.outcome, event.reason, event.actor_type, event.actor_id]
  end

  def test_post_success_redirects_with_the_default_notice
    # arrange
    configure_actions
    role_action
    account = create_account
    snapshot = role_preview(account)

    # act
    submit_action("change_user_role", role_submission(account, snapshot))

    # assert
    assert_response :redirect
    assert_equal I18n.t("lucid_backoffice.action_done"), flash[:notice]
  end

  def test_post_success_redirects_with_the_result_notice
    # arrange
    configure_actions
    role_action { result { notice "3 migrations aplicadas" } }
    account = create_account
    snapshot = role_preview(account)

    # act
    submit_action("change_user_role", role_submission(account, snapshot))

    # assert
    assert_response :redirect
    assert_equal "3 migrations aplicadas", flash[:notice]
  end

  def test_post_after_the_state_changed_is_stale_and_writes_nothing
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")
    snapshot = role_preview(account)
    account.update_column(:role, "director")

    # act
    submit_action("change_user_role", role_submission(account, snapshot))

    # assert
    assert_response :unprocessable_entity
    assert_equal I18n.t("lucid_backoffice.action_stale"), alert_text
    assert_equal "director", account.reload.role
    assert_empty action_events
  end

  def test_operator_without_the_permission_gets_403_on_get_and_post
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")

    # act
    get "#{ACTIONS}/change_user_role/new", params: { record_id: account.id, fields: { role: "coordinator" } }, headers: as(2)
    get_status = response.status
    submit_action("change_user_role", role_submission(account, "x"), operator: 2)

    # assert
    assert_equal 403, get_status
    assert_response :forbidden
    assert_equal "teacher", account.reload.role
    assert_empty action_events
  end

  def test_action_with_its_own_permission_requires_it
    # arrange
    configure_actions(permissions: { 1 => %i[run_action], 2 => %i[repair] })
    role_action { permission :repair }
    account = create_account

    # act
    open_preview("change_user_role", { record_id: account.id }, operator: 1)
    without = response.status
    open_preview("change_user_role", { record_id: account.id }, operator: 2)

    # assert
    assert_equal 403, without
    assert_response :ok
  end

  def test_unavailable_action_shows_the_explanation_instead_of_the_form
    # arrange
    configure_actions
    role_action { unavailable "Escola ficaria sem owner", if: -> { record.last_owner? } }
    account = create_account(role: "owner")

    # act
    open_preview("change_user_role", { record_id: account.id, fields: { role: "coordinator" } })

    # assert
    assert_response :ok
    assert_includes dom.at_css(".lb-flash-warn").text, "Escola ficaria sem owner"
    assert_nil snapshot_value
    assert_nil execute_button
  end

  def test_direct_post_to_an_unavailable_action_is_refused
    # arrange
    configure_actions
    role_action { unavailable "Escola ficaria sem owner", if: -> { record.last_owner? } }
    account = create_account(role: "owner")

    # act
    submit_action("change_user_role", role_submission(account, "qualquer"))

    # assert
    assert_response :unprocessable_entity
    assert_includes response.body, "Escola ficaria sem owner"
    assert_equal "owner", account.reload.role
    assert_empty action_events
  end

  def test_danger_high_shows_the_confirmation_with_the_expected_identifier
    # arrange
    configure_actions
    role_action { danger :high }
    account = create_account

    # act
    open_preview("change_user_role", { record_id: account.id, fields: { role: "coordinator" } })

    # assert
    assert_equal account.id.to_s, dom.at_css("form[data-lb-action-form]")["data-lb-expected"]
    assert dom.at_css("input[name=confirmation][data-lb-confirmation]")
  end

  def test_danger_normal_has_no_confirmation_field
    # arrange
    configure_actions
    role_action
    account = create_account

    # act
    open_preview("change_user_role", { record_id: account.id, fields: { role: "coordinator" } })

    # assert
    assert_nil dom.at_css("input[name=confirmation]")
  end

  def test_danger_high_with_a_wrong_confirmation_is_refused
    # arrange
    configure_actions
    role_action { danger :high }
    account = create_account(role: "teacher")
    snapshot = role_preview(account)

    # act
    submit_action("change_user_role", role_submission(account, snapshot, confirmation: "999999"))

    # assert
    assert_response :unprocessable_entity
    assert_includes alert_text, "confirmation"
    assert_equal "teacher", account.reload.role
    assert_empty action_events
  end

  def test_danger_high_without_a_confirmation_is_refused
    # arrange
    configure_actions
    role_action { danger :high }
    account = create_account(role: "teacher")
    snapshot = role_preview(account)

    # act
    submit_action("change_user_role", role_submission(account, snapshot))

    # assert
    assert_response :unprocessable_entity
    assert_equal "teacher", account.reload.role
  end

  def test_danger_high_with_the_right_confirmation_passes
    # arrange
    configure_actions
    role_action { danger :high }
    account = create_account(role: "teacher")
    snapshot = role_preview(account)

    # act
    submit_action("change_user_role", role_submission(account, snapshot, confirmation: account.id.to_s))

    # assert
    assert_response :redirect
    assert_equal "coordinator", account.reload.role
  end

  def test_danger_high_on_tenant_expects_the_tenant_identifier
    # arrange
    configure_actions(tenancy: ActionTenancy.new)
    define_action("RebuildIndex") { on :tenant; danger :high; perform { nil } }

    # act
    open_preview("rebuild_index", { tenant_id: "alfa" })

    # assert
    assert_equal "alfa", dom.at_css("form[data-lb-action-form]")["data-lb-expected"]
  end

  def test_transaction_false_performs_outside_a_transaction_and_records_the_event_after
    # arrange
    configure_actions
    seen = []
    role_action do
      transaction false
      perform { seen << ActiveRecord::Base.lease_connection.open_transactions; record.update!(role: role) }
    end
    account = create_account(role: "teacher")
    baseline = ActiveRecord::Base.lease_connection.open_transactions
    snapshot = role_preview(account)

    # act
    submit_action("change_user_role", role_submission(account, snapshot))

    # assert
    assert_equal [baseline], seen
    assert_equal "coordinator", account.reload.role
    assert_equal ["ok", REASON], [action_events.sole.outcome, action_events.sole.reason]
  end

  def test_transaction_true_performs_inside_a_transaction
    # arrange
    configure_actions
    seen = []
    role_action { perform { seen << ActiveRecord::Base.lease_connection.open_transactions; record.update!(role: role) } }
    account = create_account(role: "teacher")
    baseline = ActiveRecord::Base.lease_connection.open_transactions
    snapshot = role_preview(account)

    # act
    submit_action("change_user_role", role_submission(account, snapshot))

    # assert
    assert_operator seen.sole, :>, baseline
  end

  def test_field_types_render_the_right_input
    # arrange
    configure_actions
    everything_action
    create_account(role: "x")
    create_account(role: "y")

    # act
    open_preview("everything", { fields: valid_field_values })

    # assert
    assert_response :ok
    assert_equal "text", dom.at_css("input[name='fields[title]']")["type"]
    assert_equal "b", dom.at_css("textarea[name='fields[body]']").text.strip
    assert_equal ["number", "5"], dom.at_css("input[name='fields[qty]']").then { |input| [input["type"], input["value"]] }
    assert dom.at_css("input[type=checkbox][name='fields[flag]'][checked]")
    assert_equal ["date", "2026-01-02"], dom.at_css("input[name='fields[due]']").then { |input| [input["type"], input["value"]] }
    assert_equal %w[x y], dom.css("select[name='fields[kind]'] option").map { |option| option["value"] }
    assert_equal "x", dom.at_css("select[name='fields[kind]'] option[selected]")["value"]
    assert_equal ["number", "3"], dom.at_css("input[name='fields[owner]']").then { |input| [input["type"], input["value"]] }
  end

  def test_own_partial_field_renders_the_test_partial
    # arrange
    configure_actions
    everything_action
    create_account(role: "x")

    # act
    open_preview("everything", { fields: valid_field_values })

    # assert
    custom = dom.at_css(".custom-field")
    assert_equal ["custom", "c", "everything"], [custom["data-name"], custom["data-value"], custom.text]
    assert dom.at_css("input.custom-input[name='fields[custom]']")
  end

  def test_invalid_values_come_back_as_invalid_on_get
    # arrange
    configure_actions
    everything_action
    create_account(role: "x")
    cases = { qty: ["abc", "qty must be an integer"], due: ["ontem", "due must be a date"], kind: ["zzz", "kind is not one of the choices"] }

    # act
    results = cases.map do |name, (value, message)|
      open_preview("everything", { fields: valid_field_values.merge(name => value) })
      [response.status, dom.at_css(".lb-flash-error")&.text.to_s.include?(message), snapshot_value]
    end

    # assert
    assert_equal [[200, true, nil]] * 3, results
  end

  def test_invalid_values_are_refused_on_post_and_nothing_is_recorded
    # arrange
    configure_actions
    everything_action
    create_account(role: "x")
    cases = { qty: ["abc", "qty must be an integer"], due: ["ontem", "due must be a date"], kind: ["zzz", "kind is not one of the choices"] }

    # act
    results = cases.map do |name, (value, message)|
      submit_action("everything", { fields: valid_field_values.merge(name => value), snapshot: "x", reason: REASON })
      [response.status, alert_text.include?(message)]
    end

    # assert
    assert_equal [[422, true]] * 3, results
    assert_empty events("backoffice.action.everything")
  end

  def test_post_without_csrf_token_is_rejected
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")

    # act
    with_forgery_protection do
      assert_raises(ActionController::InvalidAuthenticityToken) do
        submit_action("change_user_role", role_submission(account, "x"))
      end
    end

    # assert
    assert_equal "teacher", account.reload.role
    assert_empty action_events
  end

  def test_post_with_csrf_token_is_accepted
    # arrange
    configure_actions
    role_action
    account = create_account(role: "teacher")

    # act
    with_forgery_protection do
      snapshot = role_preview(account)
      submit_action("change_user_role", role_submission(account, snapshot, authenticity_token: csrf_token))
    end

    # assert
    assert_response :redirect
    assert_equal "coordinator", account.reload.role
  end

  def test_record_screen_shows_the_action_only_to_the_operator_with_the_permission
    # arrange
    configure_actions
    role_action
    account = create_account

    # act
    get "/backoffice/data/accounts/#{account.id}", headers: as(1)
    allowed = dom.at_css("a[href*='/actions/change_user_role/new']")
    allowed_text = response.body.include?("Corrigir papel")
    get "/backoffice/data/accounts/#{account.id}", headers: as(2)

    # assert
    assert_equal "Corrigir papel", allowed.text.strip
    assert_includes allowed["href"], "record_id=#{account.id}"
    assert allowed_text
    assert_response :ok
    assert_nil dom.at_css("a[href*='/actions/']")
    refute_includes response.body, "Corrigir papel"
  end

  def test_record_screen_shows_unavailable_action_disabled_with_the_explanation
    # arrange
    configure_actions
    role_action { unavailable "Escola ficaria sem owner", if: -> { record.last_owner? } }
    account = create_account(role: "owner")

    # act
    get "/backoffice/data/accounts/#{account.id}", headers: as(1)

    # assert
    disabled = dom.at_css("span[aria-disabled=true]")
    assert_equal ["Corrigir papel", "Escola ficaria sem owner"], [disabled.text.strip, disabled["title"]]
    assert_includes response.body, "Escola ficaria sem owner"
    assert_nil dom.at_css("a[href*='/actions/change_user_role/new']")
  end

  def test_record_screen_hides_an_action_whose_only_if_is_false
    # arrange
    configure_actions
    role_action { only_if { record.owner? } }
    account = create_account(role: "teacher")

    # act
    get "/backoffice/data/accounts/#{account.id}", headers: as(1)

    # assert
    assert_response :ok
    refute_includes response.body, "Corrigir papel"
  end

  def test_tenant_screen_shows_the_tenant_action_only_to_the_operator_with_the_permission
    # arrange
    configure_actions(tenancy: ActionTenancy.new)
    define_action("RebuildIndex") { on :tenant; label "Reconstruir índice"; perform { nil } }

    # act
    get "/backoffice/tenants/alfa", headers: as(1)
    allowed = dom.at_css("a[href*='/actions/rebuild_index/new']")
    get "/backoffice/tenants/alfa", headers: as(2)

    # assert
    assert_equal "Reconstruir índice", allowed.text.strip
    assert_includes allowed["href"], "tenant_id=alfa"
    assert_response :ok
    refute_includes response.body, "Reconstruir índice"
  end

  def test_tenant_screen_shows_unavailable_action_disabled_with_the_explanation
    # arrange
    configure_actions(tenancy: ActionTenancy.new)
    define_action("RebuildIndex") do
      on :tenant
      label "Reconstruir índice"
      unavailable "Fora do ar", if: -> { tenant.code == "alfa" }
      perform { nil }
    end

    # act
    get "/backoffice/tenants/alfa", headers: as(1)

    # assert
    disabled = dom.at_css("span[aria-disabled=true]")
    assert_equal ["Reconstruir índice", "Fora do ar"], [disabled.text.strip, disabled["title"]]
    assert_nil dom.at_css("a[href*='/actions/rebuild_index/new']")
  end

  def test_dashboard_shows_the_global_action_only_to_the_operator_with_the_permission
    # arrange
    configure_actions
    define_action("PurgeCache") { on :global; label "Limpar cache"; perform { nil } }

    # act
    get "/backoffice", headers: as(1)
    allowed = dom.at_css("a[href*='/actions/purge_cache/new']")
    get "/backoffice", headers: as(2)

    # assert
    assert_equal "Limpar cache", allowed.text.strip
    assert_response :ok
    refute_includes response.body, "Limpar cache"
  end

  def test_dashboard_shows_unavailable_global_action_disabled_with_the_explanation
    # arrange
    configure_actions
    define_action("PurgeCache") { on :global; label "Limpar cache"; unavailable "Em manutenção", if: -> { true }; perform { nil } }

    # act
    get "/backoffice", headers: as(1)

    # assert
    disabled = dom.at_css("span[aria-disabled=true]")
    assert_equal ["Limpar cache", "Em manutenção"], [disabled.text.strip, disabled["title"]]
    assert_nil dom.at_css("a[href*='/actions/purge_cache/new']")
  end

  def test_tenant_action_runs_inside_tenancy_with_the_tenant
    # arrange
    configure_actions(tenancy: ActionTenancy.new)
    define_action("RebuildIndex") { on :tenant; perform { ActionTenancy.log << "perform #{tenant.code}" } }
    open_preview("rebuild_index", { tenant_id: "beta" })
    snapshot = snapshot_value
    ActionTenancy.log.clear

    # act
    submit_action("rebuild_index", { tenant_id: "beta", snapshot: snapshot, reason: REASON })

    # assert
    assert_response :redirect
    assert_equal ["enter beta", "perform beta", "exit beta"], ActionTenancy.log
  end

  def test_tenant_action_preview_is_opened_inside_tenancy_with_the_tenant
    # arrange
    configure_actions(tenancy: ActionTenancy.new)
    define_action("RebuildIndex") { on :tenant; perform { nil } }

    # act
    open_preview("rebuild_index", { tenant_id: "alfa" })

    # assert
    assert_response :ok
    assert_equal ["enter alfa", "exit alfa"], ActionTenancy.log.first(2)
  end

  def test_unknown_action_is_404_on_get_and_post
    # arrange
    configure_actions

    # act
    open_preview("nope", {})
    get_status = response.status
    submit_action("nope", { reason: REASON })

    # assert
    assert_equal 404, get_status
    assert_response :not_found
  end

  def test_action_on_a_table_without_model_is_404_on_get_and_post
    # arrange
    configure_actions
    define_action("HauntGhost") { on :ghosts; perform { nil } }

    # act
    open_preview("haunt_ghost", { record_id: 1 })
    get_status = response.status
    submit_action("haunt_ghost", { record_id: 1, snapshot: "x", reason: REASON })

    # assert
    assert_equal 404, get_status
    assert_response :not_found
  end

  def test_action_on_a_missing_record_is_404_on_get_and_post
    # arrange
    configure_actions
    role_action

    # act
    open_preview("change_user_role", { record_id: 0 })
    get_status = response.status
    submit_action("change_user_role", { record_id: 0, fields: { role: "coordinator" }, snapshot: "x", reason: REASON })

    # assert
    assert_equal 404, get_status
    assert_response :not_found
  end

  def test_action_with_an_unknown_tenant_is_404
    # arrange
    configure_actions(tenancy: ActionTenancy.new)
    define_action("RebuildIndex") { on :tenant; perform { nil } }

    # act
    open_preview("rebuild_index", { tenant_id: "zzz" })

    # assert
    assert_response :not_found
  end
end
