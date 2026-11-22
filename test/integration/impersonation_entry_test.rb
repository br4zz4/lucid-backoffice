require "integration_helper"

class ImpersonationEntryTest < ActionDispatch::IntegrationTest
  include ImpersonationSupport
  include ActiveSupport::Testing::TimeHelpers

  Impersonation = Lucid::Backoffice::Impersonation
  ENTER = "/lucid_backoffice/impersonation/enter".freeze

  def app = Rails.application

  def setup
    super
    Lucid::Backoffice.reset_configuration!
    reset_impersonation_data
    configure_impersonation
    @operator = create_operator
    host! "alfa.example.test"
  end

  def teardown
    travel_back
    reset_impersonation_data
    Lucid::Backoffice.reset_configuration!
    super
  end

  def enter(url_or_token)
    path = url_or_token.start_with?("http") ? url_or_token : "#{ENTER}?token=#{CGI.escape(url_or_token)}"
    get path
  end

  def test_successful_entry_signs_in_marks_session_and_redirects_home
    # arrange
    impersonation, url = start_impersonation(@operator)

    # act
    enter(url)

    # assert
    assert_redirected_to "/"
    assert_equal [USER_ID], @signed_in
    assert_equal USER_ID, session[:signed_in_user]
    assert_equal impersonation.id, session[:lucid_backoffice_impersonation_id]
    refute_nil impersonation.reload.entered_at
  end

  def test_successful_entry_records_enter_event_with_operator_as_actor
    # arrange
    impersonation, url = start_impersonation(@operator)
    Lucid::Backoffice::Current.reset

    # act
    enter(url)

    # assert
    event = impersonation_events("backoffice.impersonation.enter").sole
    assert_equal "ImpersonationOperator", event.actor_type
    assert_equal @operator.id, event.actor_id
    assert_equal impersonation.id, event.impersonation_id
    assert_equal REASON, event.reason
  end

  def test_token_cannot_be_used_twice
    # arrange
    _, url = start_impersonation(@operator)
    enter(url)
    @signed_in.clear

    # act
    enter(url)

    # assert
    assert_response :not_found
    assert_empty @signed_in
  end

  def test_expired_token_is_not_found
    # arrange
    _, url = start_impersonation(@operator)

    # act
    travel 61.seconds
    enter(url)

    # assert
    assert_response :not_found
    assert_empty @signed_in
  end

  def test_tampered_token_is_not_found
    # arrange
    _, url = start_impersonation(@operator)
    tampered = token_from(url).sub(/.\z/) { |char| char == "A" ? "B" : "A" }

    # act
    enter(tampered)

    # assert
    assert_response :not_found
    assert_empty @signed_in
  end

  def test_token_of_another_tenant_is_not_found_on_this_host
    # arrange
    _, url = start_impersonation(@operator, tenant: "beta")

    # act
    enter(token_from(url))

    # assert
    assert_response :not_found
    assert_empty @signed_in
    assert_nil Impersonation.last.entered_at
  end

  def test_expired_impersonation_is_not_found
    # arrange
    impersonation, url = start_impersonation(@operator)
    impersonation.update_columns(expires_at: 1.minute.ago)

    # act
    enter(url)

    # assert
    assert_response :not_found
    assert_empty @signed_in
  end

  def test_ended_impersonation_is_not_found
    # arrange
    impersonation, url = start_impersonation(@operator)
    impersonation.end!(reason: "revoked")

    # act
    enter(url)

    # assert
    assert_response :not_found
    assert_empty @signed_in
  end

  def test_missing_token_is_not_found
    # arrange
    path = ENTER

    # act
    get path

    # assert
    assert_response :not_found
  end

  def test_failed_entry_records_no_enter_event
    # arrange
    _, url = start_impersonation(@operator)
    enter(url)
    Lucid::Backoffice::Activity::Event.where(name: "backoffice.impersonation.enter").delete_all

    # act
    enter(url)

    # assert
    assert_empty impersonation_events("backoffice.impersonation.enter")
  end

  def test_destroy_ends_manually_signs_out_and_redirects_to_return_url
    # arrange
    impersonation, url = start_impersonation(@operator)
    enter(url)

    # act
    delete "/lucid_backoffice/impersonation"

    # assert
    assert_redirected_to "http://admin.example.test/backoffice"
    assert_equal "manual", impersonation.reload.end_reason
    refute_nil impersonation.ended_at
    assert_equal [true], @signed_out
    assert_nil session[:lucid_backoffice_impersonation_id]
  end

  def test_destroy_records_end_event_with_impersonation_id
    # arrange
    impersonation, url = start_impersonation(@operator)
    enter(url)

    # act
    delete "/lucid_backoffice/impersonation"

    # assert
    event = impersonation_events("backoffice.impersonation.end").sole
    assert_equal({ "reason" => "manual" }, event.payload)
    assert_equal impersonation.id, event.impersonation_id
  end

  def test_destroy_without_impersonation_still_signs_out_and_redirects
    # arrange
    path = "/lucid_backoffice/impersonation"

    # act
    delete path

    # assert
    assert_redirected_to "http://admin.example.test/backoffice"
    assert_equal [true], @signed_out
  end
end
