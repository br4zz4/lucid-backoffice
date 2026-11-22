require "test_helper"
require "impersonation_app_helper"

class ImpersonationGuardTest < ActionDispatch::IntegrationTest
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

  def test_get_passes_and_records_page_view_with_integer_id
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/students/42"

    # assert
    assert_response :success
    assert_equal({ "controller" => "guarded_app/students", "action" => "show", "id" => 42 }, page_views.sole.payload)
  end

  def test_page_view_omits_id_when_not_an_integer
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/students/abc"

    # assert
    assert_response :success
    assert_equal({ "controller" => "guarded_app/students", "action" => "show" }, page_views.sole.payload)
  end

  def test_page_view_omits_id_when_integer_has_trailing_text
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/students/12abc"

    # assert
    refute_includes page_views.sole.payload, "id"
  end

  def test_page_view_without_id_param_has_no_id
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/students"

    # assert
    assert_equal({ "controller" => "guarded_app/students", "action" => "index" }, page_views.sole.payload)
  end

  def test_page_view_sanitizes_digits_in_controller_without_breaking_the_payload_guard
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/reports2"

    # assert
    assert_response :success
    assert_equal({ "controller" => "reports", "action" => "index" }, page_views.sole.payload)
  end

  def test_page_view_sanitizes_digits_in_action
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/digits"

    # assert
    assert_response :success
    assert_equal "show", page_views.sole.payload["action"]
  end

  def test_each_get_records_one_page_view
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/students/1"
    get "/app/students/2"

    # assert
    assert_equal [1, 2], page_views.map { |event| event.payload["id"] }
  end

  [[:post, "/app/students"], [:patch, "/app/students/1"], [:put, "/app/students/1"], [:delete, "/app/students/1"]].each do |verb, path|
    define_method("test_#{verb}_is_forbidden_and_writes_nothing") do
      # arrange
      enter_impersonation(@operator)
      events_before = Lucid::Backoffice::Activity::Event.count

      # act
      public_send(verb, path)

      # assert
      assert_response :forbidden
      assert_equal 0, Widget.count
      assert_equal events_before, Lucid::Backoffice::Activity::Event.count
    end
  end

  def test_forbidden_response_is_the_read_only_message
    # arrange
    enter_impersonation(@operator)

    # act
    post "/app/students"

    # assert
    assert_equal "Impersonation is read-only", response.body
  end

  def test_read_only_except_releases_one_path
    # arrange
    Lucid::Backoffice.configuration.impersonation.read_only_except = ["/app/allowed"]
    enter_impersonation(@operator)

    # act
    post "/app/allowed"

    # assert
    assert_response :success
    assert_equal 1, Widget.count
  end

  def test_read_only_except_does_not_release_other_paths
    # arrange
    Lucid::Backoffice.configuration.impersonation.read_only_except = ["/app/allowed"]
    enter_impersonation(@operator)

    # act
    post "/app/students"

    # assert
    assert_response :forbidden
    assert_equal 0, Widget.count
  end

  def test_released_path_does_not_record_page_view
    # arrange
    Lucid::Backoffice.configuration.impersonation.read_only_except = ["/app/allowed"]
    enter_impersonation(@operator)

    # act
    post "/app/allowed"

    # assert
    assert_empty page_views
  end

  def test_without_impersonation_session_the_guard_does_nothing
    # arrange
    post "/app/login"

    # act
    post "/app/students"

    # assert
    assert_response :success
    assert_equal 1, Widget.count
    assert_empty page_views
  end

  def test_without_impersonation_session_get_records_nothing_and_is_not_impersonating
    # arrange
    path = "/app/status"

    # act
    get path

    # assert
    assert_equal "impersonating=false actor=nil", response.body
    assert_empty page_views
  end

  def test_without_impersonation_session_no_impersonation_query_runs
    # arrange
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| queries << payload[:sql] }

    # act
    get "/app/status"
    ActiveSupport::Notifications.unsubscribe(subscriber)

    # assert
    assert_empty queries.grep(/lucid_backoffice_/)
  end

  def test_expired_impersonation_ends_signs_out_and_redirects
    # arrange
    freeze_now
    enter_impersonation(@operator)
    @signed_out.clear

    # act
    travel 31.minutes
    get "/app/students/1"

    # assert
    assert_redirected_to "http://admin.example.test/backoffice"
    assert_equal "expired", Impersonation.last.end_reason
    assert_equal [true], @signed_out
    assert_empty page_views
  end

  def test_expired_impersonation_records_end_event_for_the_operator
    # arrange
    freeze_now
    enter_impersonation(@operator)

    # act
    travel 31.minutes
    get "/app/students/1"

    # assert
    event = impersonation_events("backoffice.impersonation.end").sole
    assert_equal({ "reason" => "expired" }, event.payload)
    assert_equal "ImpersonationOperator", event.actor_type
    assert_equal @operator.id, event.actor_id
  end

  def test_expired_impersonation_end_event_carries_the_impersonation_id
    # arrange
    freeze_now
    enter_impersonation(@operator)

    # act
    travel 31.minutes
    get "/app/students/1"

    # assert
    assert_equal Impersonation.last.id, impersonation_events("backoffice.impersonation.end").sole.impersonation_id
  end

  def test_expired_impersonation_blocks_writes_too
    # arrange
    freeze_now
    enter_impersonation(@operator)

    # act
    travel 31.minutes
    post "/app/students"

    # assert
    assert_redirected_to "http://admin.example.test/backoffice"
    assert_equal 0, Widget.count
  end

  def test_request_after_expiry_runs_without_impersonation
    # arrange
    freeze_now
    enter_impersonation(@operator)
    travel 31.minutes
    get "/app/students/1"

    # act
    get "/app/status"

    # assert
    assert_equal "impersonating=false actor=nil", response.body
    assert_nil session[:lucid_backoffice_impersonation_id]
  end

  def test_manually_ended_impersonation_is_redirected_on_next_use
    # arrange
    freeze_now
    impersonation, url = start_impersonation(@operator)
    get url
    impersonation.end!(reason: "revoked")
    @signed_out.clear

    # act
    get "/app/students/1"

    # assert
    assert_redirected_to "http://admin.example.test/backoffice"
    assert_equal "revoked", impersonation.reload.end_reason
    assert_equal [true], @signed_out
  end

  def test_page_view_actor_is_the_operator_with_impersonation_id
    # arrange
    enter_impersonation(@operator)

    # act
    get "/app/students/9"

    # assert
    event = page_views.sole
    assert_equal "ImpersonationOperator", event.actor_type
    assert_equal @operator.id, event.actor_id
    assert_equal Impersonation.last.id, event.impersonation_id
    assert_equal "alfa", event.tenant_identifier
  end
end
