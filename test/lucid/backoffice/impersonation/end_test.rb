require "test_helper"

class ImpersonationEndTest < BackofficeTest
  include ImpersonationSupport
  include ActiveSupport::Testing::TimeHelpers

  Impersonation = Lucid::Backoffice::Impersonation

  def setup
    super
    reset_impersonation_data
    configure_impersonation
    @operator = create_operator
  end

  def teardown
    travel_back
    reset_impersonation_data
    super
  end

  def test_active_for_finds_the_active_impersonation_of_the_user
    # arrange
    impersonation, = start_impersonation(@operator)

    # act
    found = Impersonation.active_for(user: ImpersonatedUser.new(USER_ID))

    # assert
    assert_equal impersonation, found
  end

  def test_active_for_is_nil_for_other_user
    # arrange
    start_impersonation(@operator)

    # act
    found = Impersonation.active_for(user: ImpersonatedUser.new(USER_ID + 1))

    # assert
    assert_nil found
  end

  def test_active_for_is_nil_once_ended
    # arrange
    impersonation, = start_impersonation(@operator)
    impersonation.end!

    # act
    found = Impersonation.active_for(user: ImpersonatedUser.new(USER_ID))

    # assert
    assert_nil found
  end

  def test_active_for_is_nil_once_expired
    # arrange
    start_impersonation(@operator)

    # act
    travel 31.minutes

    # assert
    assert_nil Impersonation.active_for(user: ImpersonatedUser.new(USER_ID))
  end

  def test_end_defaults_to_manual_and_records_event
    # arrange
    impersonation, = start_impersonation(@operator)

    # act
    impersonation.end!

    # assert
    assert_equal "manual", impersonation.reload.end_reason
    refute_nil impersonation.ended_at
    refute impersonation.active?
    event = impersonation_events("backoffice.impersonation.end").sole
    assert_equal({ "reason" => "manual" }, event.payload)
  end

  %w[revoked expired].each do |reason|
    define_method("test_end_with_#{reason}_records_event_with_reason_payload") do
      # arrange
      impersonation, = start_impersonation(@operator)

      # act
      impersonation.end!(reason: reason)

      # assert
      assert_equal reason, impersonation.reload.end_reason
      event = impersonation_events("backoffice.impersonation.end").sole
      assert_equal({ "reason" => reason }, event.payload)
      assert_equal "ImpersonationOperator", event.actor_type
      assert_equal @operator.id, event.actor_id
    end
  end

  def test_end_is_idempotent
    # arrange
    impersonation, = start_impersonation(@operator)
    impersonation.end!(reason: "revoked")
    ended_at = impersonation.reload.ended_at

    # act
    impersonation.end!(reason: "expired")

    # assert
    assert_equal "revoked", impersonation.reload.end_reason
    assert_equal ended_at, impersonation.ended_at
    assert_equal 1, impersonation_events("backoffice.impersonation.end").size
  end

  def test_events_carry_the_current_impersonation_id
    # arrange
    impersonation, = start_impersonation(@operator)
    Lucid::Backoffice::Current.impersonation_id = impersonation.id

    # act
    event = Lucid::Backoffice::Activity.record(name: "widget.updated", actor: @operator)

    # assert
    assert_equal impersonation.id, event.reload.impersonation_id
  end

  def test_events_without_current_impersonation_have_no_impersonation_id
    # arrange
    Lucid::Backoffice::Current.reset

    # act
    event = Lucid::Backoffice::Activity.record(name: "widget.updated", actor: @operator)

    # assert
    assert_nil event.reload.impersonation_id
  end
end
