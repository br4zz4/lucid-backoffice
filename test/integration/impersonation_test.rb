require "impersonation_app_helper"

class ImpersonationTest < ActionDispatch::IntegrationTest
  include ImpersonationSupport
  include ImpersonationAppSupport
  include ActiveSupport::Testing::TimeHelpers

  Impersonation = Lucid::Backoffice::Impersonation

  def app = Rails.application

  def setup
    super
    Lucid::Backoffice.reset_configuration!
    reset_app_data
    configure_impersonation
    @operator = create_operator
    host! "alfa.example.test"
  end

  def teardown
    travel_back
    reset_app_data
    Lucid::Backoffice.reset_configuration!
    super
  end

  def test_banner_shows_during_impersonation
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/page"

    # assert
    assert_select ".lb-impersonation-banner"
    assert_includes response.body, "Impersonating ImpersonatedUser #7 in alfa, read-only"
  end

  def test_banner_shows_the_remaining_time
    # arrange
    freeze_now
    enter_impersonation(@operator)

    # act
    travel 10.minutes
    get "/app/page"

    # assert
    assert_select "[data-lb-countdown='1200']", text: "20:00"
  end

  def test_banner_has_exit_button_that_deletes_the_impersonation
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/page"

    # assert
    assert_select "form[action='/lucid_backoffice/impersonation']" do
      assert_select "input[name='_method'][value='delete']"
    end
    assert_includes response.body, "Exit"
  end

  def test_exit_button_ends_the_impersonation_and_banner_goes_away
    # arrange
    enter_impersonation(@operator)

    # act
    delete "/lucid_backoffice/impersonation"
    get "/app/page"

    # assert
    assert_equal "manual", Impersonation.last.end_reason
    assert_select ".lb-impersonation-banner", count: 0
  end

  def test_banner_does_not_show_without_impersonation
    # arrange
    post "/app/login"

    # act
    get "/app/page"

    # assert
    assert_response :success
    assert_select ".lb-impersonation-banner", count: 0
    assert_includes response.body, "<p>page</p>"
  end

  def test_banner_is_gone_on_the_request_after_expiry
    # arrange
    freeze_now
    enter_impersonation(@operator)
    travel 31.minutes
    get "/app/page"

    # act
    get "/app/page"

    # assert
    assert_response :success
    assert_select ".lb-impersonation-banner", count: 0
  end

  def test_expired_request_redirects_instead_of_rendering
    # arrange
    freeze_now
    enter_impersonation(@operator)

    # act
    travel 31.minutes
    get "/app/page"

    # assert
    assert_redirected_to "http://admin.example.test/backoffice"
    assert_equal "expired", Impersonation.last.end_reason
    assert_equal [true], @signed_out
  end

  def test_starting_another_impersonation_replaces_the_first_one
    # arrange
    first, first_url = start_impersonation(@operator)
    get first_url
    start_impersonation(@operator)

    # act
    get "/app/page"

    # assert
    assert_equal "replaced", first.reload.end_reason
    assert_redirected_to "http://admin.example.test/backoffice"
  end

  def test_replacement_records_end_event_with_replaced_reason
    # arrange
    first, = start_impersonation(@operator)

    # act
    start_impersonation(@operator)

    # assert
    event = impersonation_events("backoffice.impersonation.end").sole
    assert_equal({ "reason" => "replaced" }, event.payload)
    assert_equal first.id, Impersonation.find(first.id).id
  end

  def test_replaced_session_runs_without_impersonation_afterwards
    # arrange
    _, first_url = start_impersonation(@operator)
    get first_url
    start_impersonation(@operator)
    get "/app/page"

    # act
    get "/app/status"

    # assert
    assert_equal "impersonating=false actor=nil", response.body
  end

  def test_events_of_the_request_have_operator_actor_and_impersonation_id
    # arrange
    impersonation, url = start_impersonation(@operator)
    get url

    # act
    get "/app/students/3"

    # assert
    event = page_views.sole
    assert_equal "ImpersonationOperator", event.actor_type
    assert_equal @operator.id, event.actor_id
    assert_equal impersonation.id, event.impersonation_id
  end

  def test_status_shows_operator_as_actor_during_impersonation
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/status"

    # assert
    assert_includes response.body, "impersonating=true"
    assert_includes response.body, "ImpersonationOperator"
  end

  def test_current_is_cleared_after_the_request
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/status"

    # assert
    assert_nil Lucid::Backoffice::Current.impersonation_id
    assert_nil Lucid::Backoffice::Current.actor
    refute Lucid::Backoffice.impersonating?
  end

  def test_current_does_not_leak_into_a_request_of_another_session
    # arrange
    enter_impersonation(@operator)
    get "/app/status"
    other = open_session { |session| session.host! "alfa.example.test" }

    # act
    other.get "/app/status"

    # assert
    assert_equal "impersonating=false actor=nil", other.response.body
  end

  def test_normal_user_request_records_no_impersonation_id_on_events
    # arrange
    post "/app/login"

    # act
    get "/app/status"

    # assert
    assert_empty page_views
    assert_empty Lucid::Backoffice::Activity::Event.where.not(impersonation_id: nil).where.not(name: "backoffice.impersonation.start")
  end
end
