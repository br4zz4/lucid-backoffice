require "test_helper"

class ImpersonationTokenTest < BackofficeTest
  include ImpersonationSupport
  include ActiveSupport::Testing::TimeHelpers

  Impersonation = Lucid::Backoffice::Impersonation
  NotFound = Lucid::Backoffice::Records::NotFound

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

  def test_enter_returns_the_impersonation_and_marks_entered_at
    # arrange
    impersonation, url = start_impersonation(@operator)
    entry_time = Time.current.change(usec: 0) + 5.seconds

    # act
    entered = travel_to(entry_time) { Impersonation.enter(token_from(url), tenant_identifier: TENANT) }

    # assert
    assert_equal impersonation, entered
    assert_equal entry_time, impersonation.reload.entered_at
  end

  def test_token_is_single_use
    # arrange
    _, url = start_impersonation(@operator)
    token = token_from(url)
    Impersonation.enter(token, tenant_identifier: TENANT)

    # act
    error = assert_raises(NotFound) { Impersonation.enter(token, tenant_identifier: TENANT) }

    # assert
    assert_equal "invalid token", error.message
  end

  def test_token_expires_after_sixty_seconds
    # arrange
    _, url = start_impersonation(@operator)
    token = token_from(url)

    # act
    travel 61.seconds

    # assert
    assert_raises(NotFound) { Impersonation.enter(token, tenant_identifier: TENANT) }
  end

  def test_token_is_valid_within_sixty_seconds
    # arrange
    impersonation, url = start_impersonation(@operator)
    token = token_from(url)

    # act
    travel 59.seconds

    # assert
    assert_equal impersonation, Impersonation.enter(token, tenant_identifier: TENANT)
  end

  def test_tampered_token_is_not_found
    # arrange
    _, url = start_impersonation(@operator)
    tampered = token_from(url).sub(/.\z/) { |char| char == "A" ? "B" : "A" }

    # act
    assert_raises(NotFound) { Impersonation.enter(tampered, tenant_identifier: TENANT) }

    # assert
    assert_nil Impersonation.last.entered_at
  end

  def test_garbage_token_is_not_found
    # arrange
    garbage = "not-a-token"

    # act / assert
    assert_raises(NotFound) { Impersonation.enter(garbage, tenant_identifier: TENANT) }
  end

  def test_token_signed_for_another_purpose_is_not_found
    # arrange
    impersonation, = start_impersonation(@operator)
    token = Rails.application.message_verifier(:other).generate(impersonation.id, purpose: :other)

    # act / assert
    assert_raises(NotFound) { Impersonation.enter(token, tenant_identifier: TENANT) }
  end

  def test_token_of_another_tenant_is_not_found
    # arrange
    _, url = start_impersonation(@operator, tenant: "beta")

    # act
    assert_raises(NotFound) { Impersonation.enter(token_from(url), tenant_identifier: TENANT) }

    # assert
    assert_nil Impersonation.last.entered_at
  end

  def test_expired_impersonation_is_not_found
    # arrange
    impersonation, url = start_impersonation(@operator)
    impersonation.update_columns(expires_at: 1.minute.ago)

    # act / assert
    assert_raises(NotFound) { Impersonation.enter(token_from(url), tenant_identifier: TENANT) }
  end

  def test_ended_impersonation_is_not_found
    # arrange
    impersonation, url = start_impersonation(@operator)
    impersonation.end!(reason: "revoked")

    # act / assert
    assert_raises(NotFound) { Impersonation.enter(token_from(url), tenant_identifier: TENANT) }
  end

  def test_replaced_impersonation_token_is_not_found
    # arrange
    _, old_url = start_impersonation(@operator)
    start_impersonation(@operator)

    # act / assert
    assert_raises(NotFound) { Impersonation.enter(token_from(old_url), tenant_identifier: TENANT) }
  end
end
