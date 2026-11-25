require "action_helper"

class ActionRunnerTest < ActionTest
  def connection
    ActiveRecord::Base.lease_connection
  end

  def test_minimal_action_writes_the_new_value
    # arrange
    configure_actions
    account = create_account(role: "teacher")

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:ok, "coordinator"], [result.status, account.reload.role]
  end

  def test_minimal_action_records_the_event_with_reason_outcome_and_operator
    # arrange
    configure_actions
    account = create_account
    Lucid::Backoffice::Current.actor = Operator.new(5)

    # act
    run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    event = action_events.sole
    assert_equal ["backoffice.action.change_user_role", "ok", REASON, Operator.name, 5], [event.name, event.outcome, event.reason, event.actor_type, event.actor_id]
  end

  def test_event_carries_the_request_id_of_current
    # arrange
    configure_actions
    account = create_account
    Lucid::Backoffice::Current.request_id = "req-1"

    # act
    run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    assert_equal "req-1", action_events.sole.request_id
  end

  def test_event_is_recorded_as_system_without_an_actor
    # arrange
    configure_actions
    account = create_account

    # act
    run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    assert_equal "System", action_events.sole.actor_type
  end

  def test_reason_is_trimmed_before_being_stored
    # arrange
    configure_actions
    account = create_account

    # act
    run_action(role_action, record: account, params: { role: "coordinator" }, reason: "  support ticket 1234  ")

    # assert
    assert_equal "support ticket 1234", action_events.sole.reason
  end

  def test_reason_shorter_than_the_minimum_is_invalid
    # arrange
    configure_actions
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" }, reason: "too short")

    # assert
    assert_equal [:invalid, "reason must have at least 10 characters"], [result.status, result.message]
  end

  def test_reason_shorter_than_the_minimum_writes_nothing
    # arrange
    configure_actions
    account = create_account

    # act
    run_action(role_action, record: account, params: { role: "coordinator" }, reason: "too short")

    # assert
    assert_equal ["teacher", 0], [account.reload.role, action_events.size]
  end

  def test_blank_reason_is_invalid
    # arrange
    configure_actions
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" }, reason: "   ")

    # assert
    assert_equal :invalid, result.status
  end

  def test_reason_minimum_follows_the_configuration
    # arrange
    configure_actions
    Lucid::Backoffice.configuration.reveal_reason_min = 30
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" }, reason: REASON)

    # assert
    assert_equal [:invalid, "reason must have at least 30 characters"], [result.status, result.message]
  end

  def test_default_authorization_denies_and_writes_nothing
    # arrange
    configure_minimal
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:forbidden, "teacher", 0], [result.status, account.reload.role, action_events.size]
  end

  def test_operator_without_run_action_is_forbidden
    # arrange
    configure_actions(permissions: %i[browse])
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:forbidden, "teacher", 0], [result.status, account.reload.role, action_events.size]
  end

  def test_missing_operator_is_forbidden
    # arrange
    configure_actions
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" }, operator: nil)

    # assert
    assert_equal [:forbidden, "teacher"], [result.status, account.reload.role]
  end

  def test_forbidden_wins_over_a_short_reason
    # arrange
    configure_minimal
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" }, reason: "x")

    # assert
    assert_equal :forbidden, result.status
  end

  def test_authorization_receives_permission_and_context
    # arrange
    received = nil
    configure_minimal do |config|
      config.authorize = lambda { |*args|
        received = args
        true
      }
    end
    operator = Operator.new(1)
    account = create_account
    tenant = { slug: "school_a" }

    # act
    run_action(role_action, record: account, tenant: tenant, params: { role: "coordinator" }, operator: operator, unlocked: [])

    # assert
    assert_equal [operator, :run_action, { tenant: tenant, record: account, action: "change_user_role" }], received
  end

  def test_custom_permission_is_the_one_asked
    # arrange
    configure_actions(permissions: %i[rewrite reveal])
    account = create_account
    action_class = role_action { permission :rewrite }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:ok, "coordinator"], [result.status, account.reload.role]
  end

  def test_run_action_is_not_enough_for_a_custom_permission
    # arrange
    configure_actions(permissions: %i[run_action])
    account = create_account
    action_class = role_action { permission :rewrite }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:forbidden, "teacher", 0], [result.status, account.reload.role, action_events.size]
  end

  def test_stale_when_the_state_changed_after_the_preview
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action_class = role_action
    snapshot = snapshot_for(action_class, record: Account.find(account.id), params: { role: "coordinator" })
    Account.where(id: account.id).update_all(role: "director")

    # act
    result = run_action(action_class, record: Account.find(account.id), params: { role: "coordinator" }, snapshot: snapshot)

    # assert
    assert_equal [:stale, "the state changed, review the preview"], [result.status, result.message]
  end

  def test_stale_writes_nothing
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action_class = role_action
    snapshot = snapshot_for(action_class, record: Account.find(account.id), params: { role: "coordinator" })
    Account.where(id: account.id).update_all(role: "director")

    # act
    run_action(action_class, record: Account.find(account.id), params: { role: "coordinator" }, snapshot: snapshot)

    # assert
    assert_equal ["director", 0], [account.reload.role, action_events.size]
  end

  def test_unchanged_state_matches_the_snapshot
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action_class = role_action
    snapshot = snapshot_for(action_class, record: Account.find(account.id), params: { role: "coordinator" })

    # act
    result = run_action(action_class, record: Account.find(account.id), params: { role: "coordinator" }, snapshot: snapshot)

    # assert
    assert_equal :ok, result.status
  end

  def test_stale_applies_to_a_custom_preview_listing
    # arrange
    configure_actions
    versions = %w[v1]
    action_class = build_action do
      on :accounts
      preview { |p| p.list "Versions", versions }
      perform { record.update!(role: "owner") }
    end
    account = create_account
    snapshot = snapshot_for(action_class, record: account)
    versions << "v2"

    # act
    result = run_action(action_class, record: account, snapshot: snapshot)

    # assert
    assert_equal [:stale, "teacher"], [result.status, account.reload.role]
  end

  def test_custom_preview_snapshot_is_accepted
    # arrange
    configure_actions
    action_class = build_action do
      on :accounts
      preview { |p| p.list "Versions", %w[v1] }
      perform { record.update!(role: "owner") }
    end
    account = create_account
    snapshot = snapshot_for(action_class, record: account)

    # act
    result = run_action(action_class, record: account, snapshot: snapshot)

    # assert
    assert_equal [:ok, "owner"], [result.status, account.reload.role]
  end

  def test_unavailable_blocks_with_the_explanation_and_writes_nothing
    # arrange
    configure_actions
    account = create_account(role: "owner")
    action_class = role_action { unavailable "School would have no owner", if: -> { record.last_owner? } }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" }, snapshot: "any")

    # assert
    assert_equal [:unavailable, "School would have no owner", "owner", 0], [result.status, result.message, account.reload.role, action_events.size]
  end

  def test_unavailable_allows_when_the_condition_is_false
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action_class = role_action { unavailable "School would have no owner", if: -> { record.last_owner? } }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal :ok, result.status
  end

  def test_only_if_blocks_with_its_reason_and_writes_nothing
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action_class = role_action { only_if("Only owners can do this") { record.owner? } }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" }, snapshot: "any")

    # assert
    assert_equal [:unavailable, "Only owners can do this", "teacher", 0], [result.status, result.message, account.reload.role, action_events.size]
  end

  def test_only_if_allows_when_satisfied
    # arrange
    configure_actions
    account = create_account(role: "owner")
    action_class = role_action { only_if("Only owners can do this") { record.owner? } }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal :ok, result.status
  end

  def test_tenant_target_exposes_the_tenant_and_no_record
    # arrange
    configure_actions
    seen = nil
    action_class = build_action("RebuildCache") do
      on :tenant
      perform { seen = [tenant, record] }
    end
    tenant = { slug: "school_a" }

    # act
    result = run_action(action_class, tenant: tenant)

    # assert
    assert_equal [:ok, [tenant, nil]], [result.status, seen]
  end

  def test_tenant_target_records_the_event
    # arrange
    configure_actions
    action_class = build_action("RebuildCache") do
      on :tenant
      perform { :done }
    end
    Lucid::Backoffice::Current.tenant_identifier = "school_a"

    # act
    run_action(action_class, tenant: { slug: "school_a" })

    # assert
    event = action_events.sole
    assert_equal ["backoffice.action.rebuild_cache", "school_a"], [event.name, event.tenant_identifier]
  end

  def test_global_target_runs_without_record_or_tenant
    # arrange
    configure_actions
    seen = nil
    action_class = build_action("Sweep") do
      on :global
      perform { seen = [tenant, record] }
    end

    # act
    result = run_action(action_class)

    # assert
    assert_equal [:ok, [nil, nil]], [result.status, seen]
  end

  def test_global_target_records_the_event
    # arrange
    configure_actions
    action_class = build_action("Sweep") do
      on :global
      perform { :done }
    end

    # act
    run_action(action_class)

    # assert
    assert_equal ["backoffice.action.sweep"], action_events.map(&:name)
  end

  def test_danger_high_requires_the_record_identifier
    # arrange
    configure_actions
    account = create_account
    action_class = role_action { danger :high }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" }, snapshot: "any", confirmation: "nope")

    # assert
    assert_equal [:invalid, "confirmation does not match", "teacher", 0], [result.status, result.message, account.reload.role, action_events.size]
  end

  def test_danger_high_without_confirmation_is_invalid
    # arrange
    configure_actions
    account = create_account
    action_class = role_action { danger :high }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" }, snapshot: "any")

    # assert
    assert_equal [:invalid, "teacher"], [result.status, account.reload.role]
  end

  def test_danger_high_runs_with_the_record_identifier
    # arrange
    configure_actions
    account = create_account
    action_class = role_action { danger :high }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" }, confirmation: account.id.to_s)

    # assert
    assert_equal [:ok, "coordinator"], [result.status, account.reload.role]
  end

  def test_danger_high_on_a_tenant_requires_the_tenant_identifier
    # arrange
    configure_actions
    Lucid::Backoffice.configuration.tenancy = TenantAdapter.new
    action_class = build_action("DropSchema") do
      on :tenant
      danger :high
      perform { :done }
    end
    tenant = { slug: "school_a" }

    # act
    results = [
      run_action(action_class, tenant: tenant, confirmation: "school_b"),
      run_action(action_class, tenant: tenant, confirmation: "school_a")
    ]

    # assert
    assert_equal [:invalid, :ok], results.map(&:status)
  end

  def test_danger_high_without_tenant_and_record_rejects_an_empty_confirmation
    # arrange
    configure_actions
    performed = false
    action_class = build_action("Sweep") do
      on :global
      danger :high
      perform { performed = true }
    end

    # act
    results = [nil, ""].map { |confirmation| run_action(action_class, snapshot: "any", confirmation: confirmation) }

    # assert
    assert_equal [[:invalid, :invalid], false, 0], [results.map(&:status), performed, action_events.size]
  end

  def test_danger_high_with_a_tenant_without_identifier_rejects_an_empty_confirmation
    # arrange
    configure_actions
    performed = false
    action_class = build_action("Sweep") do
      on :tenant
      danger :high
      perform { performed = true }
    end

    # act
    results = [nil, ""].map { |confirmation| run_action(action_class, tenant: { slug: "school_a" }, snapshot: "any", confirmation: confirmation) }

    # assert
    assert_equal [[:invalid, :invalid], false, 0], [results.map(&:status), performed, action_events.size]
  end

  def test_danger_normal_does_not_ask_for_confirmation
    # arrange
    configure_actions
    account = create_account
    action_class = role_action { danger :normal }

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal :ok, result.status
  end

  def test_transaction_true_runs_perform_inside_a_transaction
    # arrange
    configure_actions
    depth = nil
    action_class = build_action("Slow") do
      on :accounts
      perform { depth = ActiveRecord::Base.lease_connection.open_transactions }
    end
    account = create_account

    # act
    run_action(action_class, record: account)

    # assert
    assert_equal 1, depth
  end

  def test_transaction_false_runs_perform_without_a_transaction
    # arrange
    configure_actions
    depth = nil
    action_class = build_action("CallApi") do
      on :accounts
      transaction false
      perform { depth = ActiveRecord::Base.lease_connection.open_transactions }
    end
    account = create_account

    # act
    run_action(action_class, record: account)

    # assert
    assert_equal 0, depth
  end

  def test_transaction_false_records_the_event_after_perform
    # arrange
    configure_actions
    during = nil
    action_class = build_action("CallApi") do
      on :accounts
      transaction false
      perform { during = Lucid::Backoffice::Activity::Event.where(name: "backoffice.action.call_api").count }
    end
    account = create_account

    # act
    run_action(action_class, record: account)

    # assert
    assert_equal [0, 1], [during, action_events("backoffice.action.call_api").size]
  end

  def capture_statements
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end

  def commits_between_write_and_event(transaction)
    action_class = build_action("CallApi") do
      on :accounts
      self.transaction(transaction)
      perform { record.update!(role: "coordinator") }
    end
    account = create_account
    statements = capture_statements { run_action(action_class, record: account) }
    update = statements.index { |sql| sql.start_with?("UPDATE \"accounts\"") }
    insert = statements.index { |sql| sql.start_with?("INSERT INTO \"lucid_backoffice_activity_events\"") }
    statements[update..insert].count("COMMIT")
  end

  def test_transaction_false_commits_the_write_before_the_event_is_recorded
    # arrange
    configure_actions

    # act
    commits = commits_between_write_and_event(false)

    # assert
    assert_equal 1, commits
  end

  def test_transaction_true_records_the_event_before_the_commit_of_the_write
    # arrange
    configure_actions

    # act
    commits = commits_between_write_and_event(true)

    # assert
    assert_equal 0, commits
  end

  def test_transaction_false_keeps_the_writes_when_perform_fails
    # arrange
    configure_actions
    action_class = build_action("CallApi") do
      on :accounts
      transaction false
      perform do
        record.update!(role: "coordinator")
        Failure.new(:remote_down)
      end
    end
    account = create_account

    # act
    result = run_action(action_class, record: account)

    # assert
    assert_equal [:failed, "coordinator", "remote_down"], [result.status, account.reload.role, action_events.sole.outcome]
  end

  def test_transaction_false_exception_propagates_without_event
    # arrange
    configure_actions
    action_class = build_action("CallApi") do
      on :accounts
      transaction false
      perform { raise "boom" }
    end
    account = create_account

    # act
    error = assert_raises(RuntimeError) { run_action(action_class, record: account) }

    # assert
    assert_equal ["boom", 0], [error.message, action_events.size]
  end

  def test_failure_result_records_its_type_as_outcome_and_undoes_the_write
    # arrange
    configure_actions
    action_class = role_action do
      perform do
        record.update!(role: role)
        Failure.new(:last_owner)
      end
    end
    account = create_account

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:failed, "Last owner", "teacher", "last_owner"], [result.status, result.message, account.reload.role, action_events.sole.outcome]
  end

  def test_failure_result_keeps_the_reason_in_the_event
    # arrange
    configure_actions
    action_class = role_action { perform { Failure.new(:last_owner) } }
    account = create_account

    # act
    run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal REASON, action_events.sole.reason
  end

  def test_failure_result_carries_the_returned_value
    # arrange
    configure_actions
    failure = Failure.new(:last_owner)
    action_class = role_action { perform { failure } }
    account = create_account

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_same failure, result.value
  end

  def test_exception_propagates_without_event_and_undoes_the_write
    # arrange
    configure_actions
    action_class = role_action do
      perform do
        record.update!(role: role)
        raise "boom"
      end
    end
    account = create_account

    # act
    error = assert_raises(RuntimeError) { run_action(action_class, record: account, params: { role: "coordinator" }) }

    # assert
    assert_equal ["boom", "teacher", 0], [error.message, account.reload.role, action_events.size]
  end

  def test_result_block_becomes_the_message
    # arrange
    configure_actions
    action_class = role_action { result { notice "3 migrations applied" } }
    account = create_account

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:ok, "3 migrations applied"], [result.status, result.message]
  end

  def test_result_block_receives_the_value_returned_by_perform
    # arrange
    configure_actions
    action_class = build_action("Migrate") do
      on :global
      perform { 3 }
      result { |count| notice "#{count} migrations applied" }
    end

    # act
    result = run_action(action_class)

    # assert
    assert_equal ["3 migrations applied", 3], [result.message, result.value]
  end

  def test_without_result_block_the_message_is_nil
    # arrange
    configure_actions
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    assert_nil result.message
  end

  def test_result_is_ok_predicate
    # arrange
    configure_actions
    account = create_account

    # act
    results = [run_action(role_action, record: account, params: { role: "coordinator" }), run_action(role_action, record: account, params: { role: "x" }, snapshot: "any")]

    # assert
    assert_equal [true, false], results.map(&:ok?)
  end

  def test_redirect_block_receives_the_value_returned_by_perform
    # arrange
    configure_actions
    action_class = build_action("Provision") do
      on :global
      perform { { slug: "alfa", count: 2 } }
      redirect_to { |value| "https://other.example.test/schools/#{value[:slug]}" }
    end

    # act
    result = run_action(action_class)

    # assert
    assert_equal "https://other.example.test/schools/alfa", result.redirect
    assert_predicate result, :ok?
  end

  def test_redirect_is_nil_without_redirect_to
    # arrange
    configure_actions
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    assert_nil result.redirect
  end

  def test_failure_result_has_no_redirect_and_does_not_evaluate_the_block
    # arrange
    configure_actions
    evaluated = []
    action_class = build_action("Provision") do
      on :global
      perform { Failure.new(:remote_down) }
      redirect_to { |value| evaluated << value && "/somewhere" }
    end

    # act
    result = run_action(action_class)

    # assert
    assert_nil result.redirect
    refute_predicate result, :ok?
    assert_empty evaluated
  end

  def test_result_new_without_redirect_defaults_to_nil
    # arrange
    # act
    result = Action::Result.new(status: :ok, message: "done", value: 1)

    # assert
    assert_nil result.redirect
    assert_predicate result, :ok?
    assert_equal [:ok, "done", 1], [result.status, result.message, result.value]
  end

  def test_result_new_accepts_a_redirect
    # arrange
    # act
    result = Action::Result.new(status: :ok, message: nil, value: nil, redirect: "/x")

    # assert
    assert_equal "/x", result.redirect
  end

  def test_perform_reads_the_reason_typed_by_the_operator
    # arrange
    configure_actions
    seen = []
    action_class = build_action("Provision") do
      on :global
      perform { seen << reason }
    end

    # act
    run_action(action_class)

    # assert
    assert_equal [REASON], seen
    assert_equal REASON, action_events("backoffice.action.provision").sole.reason
  end

  def test_redirect_to_reads_the_reason_typed_by_the_operator
    # arrange
    configure_actions
    action_class = build_action("Provision") do
      on :global
      perform { 1 }
      redirect_to { |_value| "/audit?reason=#{reason}" }
    end

    # act
    result = run_action(action_class)

    # assert
    assert_equal "/audit?reason=#{REASON}", result.redirect
  end

  def test_reason_is_nil_when_the_action_is_built_directly
    # arrange
    action = build_action("Provision") { on :global }.new

    # act
    reason = action.reason

    # assert
    assert_nil reason
  end

  def submit_action_class(performed: [], &extra)
    build_action("SendReport") do
      on :global
      submit :screen, label: "Mostrar na tela"
      submit :email, label: "Enviar por e-mail", if: -> { email_available? }
      perform { performed << submitted }
      class_eval(&extra) if extra
    end
  end

  def test_declared_submit_option_runs_and_is_visible_to_perform
    # arrange
    configure_actions
    performed = []
    action_class = submit_action_class(performed: performed)

    # act
    result = run_action(action_class, submit: "screen")

    # assert
    assert_equal [:ok, [:screen]], [result.status, performed]
  end

  def test_submit_option_whose_condition_fails_is_invalid_and_nothing_runs
    # arrange
    configure_actions
    Lucid::Backoffice.configuration.email_available = -> { false }
    performed = []
    action_class = submit_action_class(performed: performed)

    # act
    result = run_action(action_class, submit: "email")

    # assert
    assert_equal [:invalid, [], 0], [result.status, performed, action_events.size]
  end

  def test_submit_option_whose_condition_holds_runs
    # arrange
    configure_actions
    Lucid::Backoffice.configuration.email_available = -> { true }
    performed = []
    action_class = submit_action_class(performed: performed)

    # act
    result = run_action(action_class, submit: "email")

    # assert
    assert_equal [:ok, [:email]], [result.status, performed]
  end

  def test_unknown_submit_option_is_invalid
    # arrange
    configure_actions
    performed = []
    action_class = submit_action_class(performed: performed)

    # act
    result = run_action(action_class, submit: "carrier_pigeon")

    # assert
    assert_equal [:invalid, [], 0], [result.status, performed, action_events.size]
  end

  def test_missing_submit_is_invalid_when_the_action_declares_submits
    # arrange
    configure_actions
    performed = []
    action_class = submit_action_class(performed: performed)

    # act
    results = [run_action(action_class), run_action(action_class, submit: "")]

    # assert
    assert_equal [[:invalid, :invalid], [], 0], [results.map(&:status), performed, action_events.size]
  end

  def test_submit_is_ignored_when_the_action_declares_no_submits
    # arrange
    configure_actions
    performed = []
    action_class = build_action("Sweep") do
      on :global
      perform { performed << submitted }
    end

    # act
    result = run_action(action_class, submit: "email")

    # assert
    assert_equal [:ok, [:email]], [result.status, performed]
  end

  def test_invalid_submit_does_not_open_the_event_or_touch_the_record
    # arrange
    configure_actions
    Lucid::Backoffice.configuration.email_available = -> { false }
    account = create_account(role: "teacher")
    action_class = role_action do
      submit :email, label: "Enviar", if: -> { email_available? }
    end

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" }, submit: "email")

    # assert
    assert_equal [:invalid, "teacher", 0], [result.status, account.reload.role, action_events.size]
  end

  def test_secret_is_carried_by_the_result_on_success
    # arrange
    configure_actions
    action_class = role_action { secret { |value| "link-#{value}" } }
    account = create_account

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:ok, "link-#{result.value}"], [result.status, result.secret]
  end

  def test_secret_is_nil_when_the_action_declares_none
    # arrange
    configure_actions
    account = create_account

    # act
    result = run_action(role_action, record: account, params: { role: "coordinator" })

    # assert
    assert_nil result.secret
  end

  def test_secret_is_nil_when_the_block_returns_blank
    # arrange
    configure_actions
    action_class = role_action { secret { |_value| "" } }
    account = create_account

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_nil result.secret
  end

  def test_secret_is_nil_on_failure
    # arrange
    configure_actions
    action_class = role_action do
      secret { |_value| "nunca-exibir" }
      perform { Failure.new(:last_owner) }
    end
    account = create_account

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    assert_equal [:failed, nil], [result.status, result.secret]
  end

  def test_secret_is_absent_from_the_recorded_event
    # arrange
    configure_actions
    action_class = role_action { secret { |_value| "SEGREDO-NO-EVENTO" } }
    account = create_account

    # act
    run_action(action_class, record: account, params: { role: "coordinator" })

    # assert
    refute_includes action_events.sole.attributes.to_json, "SEGREDO-NO-EVENTO"
  end
end
