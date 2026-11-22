require "integration_helper"

class AccessIntegrationTest < PanelTest
  def test_request_without_operator_calls_authenticate_and_queries_no_data
    # arrange
    configure_panel(permissions: { 1 => %i[browse] })
    insert_student

    # act
    statements = capture_sql { get "/backoffice/data/students" }

    # assert
    assert_equal 1, @authenticate_calls
    assert_redirected_to "/login"
    assert_empty statements.grep(TABLE_SQL)
    refute_leaks response.body
  end

  def test_every_screen_without_operator_redirects_to_login
    # arrange
    configure_panel(permissions: { 1 => %i[browse view_activity view_dashboard] })

    # act
    results = ["/backoffice", "/backoffice/data", "/backoffice/activity"].map do |path|
      get path
      response.location
    end

    # assert
    assert_equal ["http://www.example.com/login"] * 3, results
  end

  def test_default_denies_every_screen_for_authenticated_operator
    # arrange
    configure_panel

    # act
    statuses = ["/backoffice", "/backoffice/data", "/backoffice/data/students", "/backoffice/activity"].map do |path|
      get path, headers: as(1)
      response.status
    end

    # assert
    assert_equal [403] * 4, statuses
  end

  def test_default_denies_reveal
    # arrange
    configure_panel

    # act
    post "/backoffice/reveals", params: { category: "contact", reason: "investigar chamado 123" }, headers: as(1)

    # assert
    assert_response :forbidden
    assert_equal 0, Lucid::Backoffice::Reveal.count
  end

  def test_browse_permission_lists_table_but_reveal_is_forbidden
    # arrange
    configure_panel(permissions: { 1 => %i[browse] })
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)
    list_status = response.status
    post "/backoffice/reveals", params: { category: "contact", reason: "investigar chamado 123" }, headers: as(1)

    # assert
    assert_equal 200, list_status
    assert_response :forbidden
    assert_equal 0, Lucid::Backoffice::Reveal.count
  end

  def test_permissions_are_per_operator
    # arrange
    configure_panel(permissions: { 1 => %i[browse], 2 => [] })

    # act
    get "/backoffice/data", headers: as(2)
    denied = response.status
    get "/backoffice/data", headers: as(1)

    # assert
    assert_equal 403, denied
    assert_response :ok
  end

  def test_authorize_receives_table_and_model_context
    # arrange
    contexts = []
    configure_panel { |config| config.authorize = ->(_operator, _permission, context) { contexts << context && true } }

    # act
    get "/backoffice/data/students", headers: as(1)

    # assert
    assert_response :ok
    assert(contexts.any? { |context| context[:table] == "students" && context.key?(:model) })
  end

  def test_post_without_csrf_token_is_rejected
    # arrange
    configure_panel(permissions: { 1 => %i[reveal browse] })

    # act
    with_forgery_protection do
      assert_raises(ActionController::InvalidAuthenticityToken) do
        post "/backoffice/reveals", params: { category: "contact", reason: "investigar chamado 123" }, headers: as(1)
      end
    end

    # assert
    assert_equal 0, Lucid::Backoffice::Reveal.count
  end

  def test_post_with_csrf_token_is_accepted
    # arrange
    configure_panel(permissions: { 1 => %i[reveal browse] })

    # act
    with_forgery_protection do
      get "/backoffice/data", headers: as(1)
      post "/backoffice/reveals", params: { category: "contact", reason: "investigar chamado 123", authenticity_token: csrf_token },
                                  headers: as(1)
    end

    # assert
    assert_response :redirect
    assert_equal 1, Lucid::Backoffice::Reveal.count
  end

  def test_delete_without_csrf_token_is_rejected
    # arrange
    configure_panel(permissions: { 1 => %i[reveal] })
    reveal = Lucid::Backoffice::Reveal.grant(operator: PanelOperator.new(1), category: "contact", reason: "investigar chamado 123")

    # act
    with_forgery_protection do
      assert_raises(ActionController::InvalidAuthenticityToken) { delete "/backoffice/reveals/#{reveal.id}", headers: as(1) }
    end

    # assert
    assert_nil reveal.reload.revoked_at
  end

  def test_only_post_and_delete_reveals_are_not_get
    # arrange
    routes = Lucid::Backoffice::Engine.routes.routes

    # act
    writing = routes.reject { |route| route.verb == "GET" }.map { |route| [route.verb, route.path.spec.to_s.sub("(.:format)", "")] }

    # assert
    assert_equal [["POST", "/reveals"], ["DELETE", "/reveals/:id"], ["POST", "/actions/:action_key"]].sort, writing.sort
  end
end
