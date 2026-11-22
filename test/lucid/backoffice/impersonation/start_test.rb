require "test_helper"

class ImpersonationStartTest < BackofficeTest
  include ImpersonationSupport
  include ActiveSupport::Testing::TimeHelpers

  Impersonation = Lucid::Backoffice::Impersonation

  def setup
    super
    reset_impersonation_data
  end

  def teardown
    travel_back
    reset_impersonation_data
    super
  end

  def test_without_permission_is_forbidden_and_creates_nothing
    # arrange
    configure_impersonation(permissions: [])
    operator = create_operator

    # act
    error = assert_raises(Lucid::Backoffice::Error::Forbidden) { start_impersonation(operator) }

    # assert
    assert_includes error.message, "impersonate"
    assert_equal 0, Impersonation.count
    assert_empty impersonation_events("backoffice.impersonation.start")
  end

  def test_short_reason_raises_record_invalid_and_creates_nothing
    # arrange
    configure_impersonation
    operator = create_operator

    # act
    assert_raises(ActiveRecord::RecordInvalid) { start_impersonation(operator, reason: "curto") }

    # assert
    assert_equal 0, Impersonation.count
    assert_empty impersonation_events("backoffice.impersonation.start")
  end

  def test_blank_reason_raises_record_invalid
    # arrange
    configure_impersonation
    operator = create_operator

    # act
    assert_raises(ActiveRecord::RecordInvalid) { start_impersonation(operator, reason: "          ") }

    # assert
    assert_equal 0, Impersonation.count
  end

  def test_unknown_user_raises_not_found_and_creates_nothing
    # arrange
    configure_impersonation
    operator = create_operator

    # act
    assert_raises(Lucid::Backoffice::Records::NotFound) { start_impersonation(operator, user_id: 999) }

    # assert
    assert_equal 0, Impersonation.count
    assert_empty impersonation_events("backoffice.impersonation.start")
  end

  def test_creates_record_with_expiry_and_metadata
    # arrange
    configure_impersonation(duration: 30 * 60)
    operator = create_operator
    now = Time.utc(2026, 11, 21, 12, 0, 0)

    # act
    impersonation, = travel_to(now) { start_impersonation(operator, metadata: { "ticket" => "4321" }) }

    # assert
    assert_equal 1, Impersonation.count
    assert_equal "ImpersonationOperator", impersonation.operator_type
    assert_equal operator.id, impersonation.operator_id
    assert_equal "ImpersonatedUser", impersonation.user_type
    assert_equal USER_ID, impersonation.user_id
    assert_equal TENANT, impersonation.tenant_identifier
    assert_equal REASON, impersonation.reason
    assert_equal({ "ticket" => "4321" }, impersonation.reload.metadata)
    assert_equal now, impersonation.started_at
    assert_equal now + 30.minutes, impersonation.expires_at
    assert_nil impersonation.entered_at
    assert_nil impersonation.ended_at
  end

  def test_records_start_event_with_reason_and_actor
    # arrange
    configure_impersonation
    operator = create_operator

    # act
    impersonation, = start_impersonation(operator)

    # assert
    event = impersonation_events("backoffice.impersonation.start").sole
    assert_equal REASON, event.reason
    assert_equal "ImpersonationOperator", event.actor_type
    assert_equal operator.id, event.actor_id
    assert_equal impersonation.id, event.impersonation_id
  end

  def test_returns_entry_url_with_token_for_the_impersonation
    # arrange
    configure_impersonation
    operator = create_operator

    # act
    impersonation, url = start_impersonation(operator)

    # assert
    assert url.start_with?("http://alfa.example.test/lucid_backoffice/impersonation/enter?token=")
    assert_equal impersonation.id, Impersonation.verifier.verify(token_from(url), purpose: Impersonation::PURPOSE)
  end

  def test_new_impersonation_of_same_operator_ends_the_previous_as_replaced
    # arrange
    configure_impersonation
    operator = create_operator
    first, = start_impersonation(operator)

    # act
    second, = start_impersonation(operator)

    # assert
    assert_equal "replaced", first.reload.end_reason
    refute_nil first.ended_at
    assert_nil second.reload.ended_at
    assert_equal [second], Impersonation.active.to_a
    assert_equal({ "reason" => "replaced" }, impersonation_events("backoffice.impersonation.end").sole.payload)
  end

  def test_new_impersonation_does_not_end_another_operators
    # arrange
    configure_impersonation
    first_operator = create_operator("um")
    second_operator = create_operator("dois")
    first, = start_impersonation(first_operator)

    # act
    start_impersonation(second_operator)

    # assert
    assert_nil first.reload.ended_at
    assert_equal 2, Impersonation.active.count
  end
end
