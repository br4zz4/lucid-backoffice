require "action_helper"
require "lucid/case"
require "lucid/backoffice/integrations/lucid_case"

module Accounts
  class ChangeRole < Lucid::Case::Command
    attributes :role, :record

    validates :role, inclusion: { in: %w[teacher coordinator] }

    def call!
      record.update!(role: role)
      success(account: record)
    end
  end

  class ChangeRoleGuarded < Lucid::Case::Command
    attributes :role, :record

    fail_if :last_owner?

    def call!
      record.update!(role: role)
      success(account: record)
    end

    private

    def last_owner? = record.owner?
  end

  class ChangeRoleTyped < Lucid::Case::Command
    attributes :role, :record

    def call!
      record.update!(role: role)
      failure(:no_seats)
    end
  end

  class ChangeRoleWithTenant < Lucid::Case::Command
    attributes :role, :tenant

    def call!
      success(seen: tenant)
    end
  end

  class ChangeRoleWithoutRecord < Lucid::Case::Command
    attributes :role

    def call!
      success(seen: role)
    end
  end
end

module Accounts
  class Notify < Lucid::Case::Command
    attributes :role, :record, :submit

    def call!
      success(via: submit)
    end
  end
end

class LucidCaseActionTest < ActionTest
  def setup
    super
    I18n.backend.send(:init_translations)
    @observers_before = Lucid::Case.configuration.events.observers.dup
    Lucid::Backoffice::Integrations::LucidCase.install!
    Lucid::Backoffice::Action.reset!
  end

  def teardown
    Lucid::Case.configuration.events.observers.replace(@observers_before)
    Lucid::Case.configuration.events.recording = :disabled
    Lucid::Backoffice::Action.reset!
    I18n.backend.reload!
    super
  end

  def command_action(command, name = "ChangeUserRole")
    build_action(name) do
      on :accounts
      field :role, :select, choices: -> { %w[teacher coordinator owner] }
      perform with: command
    end
  end

  def i18n_failure(key, type, text)
    I18n.backend.store_translations(:en, lucid_backoffice: { actions: { key => { failures: { type => text } } } })
  end

  def test_command_receives_the_current_value_of_a_locked_field
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action = command_action(Accounts::ChangeRole)
    snapshot = snapshot_for(action, record: account, params: { role: "teacher" })

    # act
    result = run_action(action, record: account, params: { role: "coordinator" }, snapshot: snapshot, revealed: [])

    # assert
    assert_equal [:ok, "teacher"], [result.status, account.reload.role]
  end

  def test_command_receives_the_submitted_value_when_the_field_is_revealed
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action = command_action(Accounts::ChangeRole)

    # act
    result = run_action(action, record: account, params: { role: "coordinator" }, revealed: %w[contact])

    # assert
    assert_equal [:ok, "coordinator"], [result.status, account.reload.role]
  end

  def test_fields_become_attributes_and_record_is_passed
    # arrange
    configure_actions
    account = create_account(role: "teacher")

    # act
    result = run_action(command_action(Accounts::ChangeRole), record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:ok, "coordinator"], [result.status, account.reload.role]
    assert_equal account, result.value[:account]
  end

  def test_record_is_not_passed_when_the_command_does_not_declare_it
    # arrange
    configure_actions
    account = create_account

    # act
    result = run_action(command_action(Accounts::ChangeRoleWithoutRecord), record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:ok, "coordinator"], [result.status, result.value[:seen]]
  end

  def test_tenant_is_passed_when_the_command_declares_it
    # arrange
    configure_actions
    tenant = { slug: "alfa" }
    action = build_action("ChangeUserRole") do
      on :tenant
      field :role, :select, choices: -> { %w[teacher] }
      perform with: Accounts::ChangeRoleWithTenant
    end

    # act
    result = run_action(action, tenant: tenant, params: { role: "teacher" })

    # assert
    assert_equal [:ok, tenant], [result.status, result.value[:seen]]
  end

  def test_command_validation_failure_shows_the_validation_message_and_writes_nothing
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action = build_action("ChangeUserRole") do
      on :accounts
      field :role, :string
      perform with: Accounts::ChangeRole
    end

    # act
    result = run_action(action, record: account, params: { role: "janitor" })

    # assert
    assert_equal :failed, result.status
    assert_match(/role/i, result.message)
    assert_equal "teacher", account.reload.role
  end

  def test_guard_failure_shows_the_errors_message_and_the_write_is_gone
    # arrange
    configure_actions
    account = create_account(role: "owner")
    I18n.backend.store_translations(:en, accounts: { change_role_guarded: { last_owner: "School would have no owner" } })

    # act
    result = run_action(command_action(Accounts::ChangeRoleGuarded), record: account, params: { role: "teacher" })

    # assert
    assert_equal :failed, result.status
    assert_equal "School would have no owner", result.message
    assert_equal "owner", account.reload.role
  end

  def test_failure_without_errors_uses_the_i18n_failure_key
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    i18n_failure("change_user_role", "no_seats", "No seats left on the plan")

    # act
    result = run_action(command_action(Accounts::ChangeRoleTyped), record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:failed, "No seats left on the plan"], [result.status, result.message]
    assert_equal "teacher", account.reload.role
  end

  def test_failure_without_errors_and_without_key_falls_back_to_the_humanized_type
    # arrange
    configure_actions
    account = create_account(role: "teacher")

    # act
    result = run_action(command_action(Accounts::ChangeRoleTyped, "UnknownKeyAction"), record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:failed, "No seats"], [result.status, result.message]
    assert_equal "teacher", account.reload.role
  end

  def test_success_writes_and_records_both_events_with_the_same_request_id_and_the_reason
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    Lucid::Backoffice::Current.request_id = "req-42"

    # act
    run_action(command_action(Accounts::ChangeRole), record: account, params: { role: "coordinator" })

    # assert
    assert_equal "coordinator", account.reload.role
    assert_equal ["accounts.change_role", "backoffice.action.change_user_role"], action_events.map(&:name).sort_by { |name| name.start_with?("backoffice") ? 1 : 0 }
    assert_equal ["req-42"], action_events.map(&:request_id).uniq
    assert_equal [REASON], action_events.map(&:reason).compact.uniq
    assert_equal REASON, action_events("backoffice.action.change_user_role").sole.reason
    assert_equal "ok", action_events("accounts.change_role").sole.outcome
  end

  def test_command_event_records_the_subject_and_changed_field
    # arrange
    configure_actions
    account = create_account(role: "teacher")

    # act
    run_action(command_action(Accounts::ChangeRole), record: account, params: { role: "coordinator" })

    # assert
    event = action_events("accounts.change_role").sole
    assert_equal [{ "type" => "Account", "id" => account.id }], event.subjects
    assert_equal ["role"], event.changed_fields
  end

  def test_guard_failure_records_the_command_event_and_the_action_event_with_the_failure_outcome
    # arrange
    configure_actions
    account = create_account(role: "owner")

    # act
    run_action(command_action(Accounts::ChangeRoleGuarded), record: account, params: { role: "teacher" })

    # assert
    assert_equal "last_owner", action_events("backoffice.action.change_user_role").sole.outcome
    assert_equal ["last_owner"], action_events("accounts.change_role_guarded").map(&:outcome)
  end

  def test_command_declaring_submit_receives_the_chosen_option_as_a_symbol
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action = build_action do
      on :accounts
      field :role, :select, choices: -> { %w[teacher coordinator owner] }
      submit :email, label: "Enviar por e-mail"
      submit :screen, label: "Mostrar na tela"
      perform with: Accounts::Notify
    end

    # act
    result = run_action(action, record: account, params: { role: "coordinator" }, submit: "email")

    # assert
    assert_equal [:ok, :email], [result.status, result.value[:via]]
  end

  def test_command_without_a_submit_attribute_runs_with_a_declared_submit
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action = build_action do
      on :accounts
      field :role, :select, choices: -> { %w[teacher coordinator owner] }
      submit :screen, label: "Mostrar na tela"
      perform with: Accounts::ChangeRole
    end

    # act
    result = run_action(action, record: account, params: { role: "coordinator" }, submit: "screen")

    # assert
    assert_equal [:ok, "coordinator"], [result.status, account.reload.role]
  end
end
