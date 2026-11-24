require "integration_helper"
require "action_helper"

class SecretIntegrationTest < PanelTest
  ACTIONS = "/backoffice/actions".freeze
  REASON = "investigar chamado 123".freeze
  SECRET = "SEGREDO-UNICO-9f3a7c".freeze
  OPERATOR = { 1 => %i[run_action browse view_dashboard view_tenant] }.freeze

  def setup
    super
    Lucid::Backoffice::Action.reset!
    Account.delete_all
  end

  def teardown
    Lucid::Backoffice::Action.reset!
    Account.delete_all
    super
  end

  def configure_actions
    path = write_yaml(ActionTest::CLASSIFICATION)
    configure_panel(permissions: OPERATOR) { |config| config.classification_path = path }
    Lucid::Backoffice::Reveal.create!(operator_type: "PanelOperator", operator_id: 1, tenant_identifier: Lucid::Backoffice::Reveal.tenant_identifier(nil),
                                      category: "contact", reason: REASON, expires_at: 1.hour.from_now)
  end

  def define_action(name, &body)
    klass = Class.new(Lucid::Backoffice::Action)
    klass.define_singleton_method(:name) { name }
    klass.class_eval(&body)
    klass
  end

  def secret_action(secret_value = SECRET, outcome: nil)
    define_action("IssueLink") do
      on :accounts
      label "Gerar link"
      field :role, :select, choices: -> { %w[teacher coordinator director] }
      perform do
        record.update!(role: role)
        outcome || record.id
      end
      secret { |_value| secret_value }
    end
  end

  def create_account = Account.create!(role: "teacher", nickname: "Mia", level: 1)

  def submit(account, key: "issue_link")
    get "#{ACTIONS}/#{key}/new", params: { record_id: account.id, fields: { role: "coordinator" } }, headers: as(1)
    snapshot = dom.at_css("input[name=snapshot]")["value"]
    nonce = dom.at_css("input[name=nonce]")&.[]("value")
    @last_params = { record_id: account.id, fields: { role: "coordinator" }, snapshot: snapshot, reason: REASON, nonce: nonce }.compact
    post "#{ACTIONS}/#{key}", params: @last_params, headers: as(1)
  end

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    logger.level = Logger::DEBUG
    Rails.logger.broadcast_to(logger)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  def test_secret_is_rendered_on_the_response_without_redirect
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    submit(account)

    # assert
    assert_response :success
    assert_equal "coordinator", account.reload.role
  end

  def test_response_is_not_cacheable
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    submit(account)

    # assert
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  def test_secret_is_in_a_readonly_input_with_a_copy_button
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    submit(account)

    # assert
    input = dom.at_css("input[readonly]")
    assert_equal SECRET, input["value"]
    assert dom.at_css("[data-lb-copy]")
  end

  def test_no_link_carries_the_secret
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    submit(account)

    # assert
    hrefs = dom.css("a[href]").map { |node| node["href"] }
    assert_empty hrefs.select { |href| href.include?(SECRET) || href.include?(CGI.escape(SECRET)) }
    assert dom.at_css("a[href]")
  end

  def test_secret_is_absent_from_flash_and_session
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    submit(account)

    # assert
    assert_empty flash.to_h.to_s.scan(SECRET)
    assert_empty session.to_h.to_s.scan(SECRET)
    assert_empty response.headers["Set-Cookie"].to_s.scan(SECRET)
  end

  def test_secret_is_absent_from_the_event
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    submit(account)

    # assert
    assert_equal 1, events("backoffice.action.issue_link").size
    events.each { |event| refute_includes event.attributes.to_json, SECRET }
  end

  def test_secret_is_absent_from_the_request_log
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    log = capture_log { submit(account) }

    # assert
    assert_includes log, "issue_link"
    refute_includes log, SECRET
  end

  def test_secret_is_not_shown_again_on_the_next_page
    # arrange
    configure_actions
    secret_action
    account = create_account
    submit(account)

    # act
    get dom.at_css("a.lb-button[href]")["href"], headers: as(1)

    # assert
    refute_includes response.body, SECRET
    assert_empty flash.to_h.to_s.scan(SECRET)
  end

  def test_replaying_a_get_of_the_action_does_not_show_the_secret
    # arrange
    configure_actions
    secret_action
    account = create_account
    submit(account)

    # act
    get "#{ACTIONS}/issue_link/new", params: { record_id: account.id }, headers: as(1)

    # assert
    refute_includes response.body, SECRET
  end

  def test_nil_secret_follows_the_normal_redirect_with_notice
    # arrange
    configure_actions
    secret_action(nil)
    account = create_account

    # act
    submit(account)

    # assert
    assert_response :redirect
    assert_equal I18n.t("lucid_backoffice.action_done"), flash[:notice]
  end

  def test_empty_secret_follows_the_normal_redirect_with_notice
    # arrange
    configure_actions
    secret_action("")
    account = create_account

    # act
    submit(account)

    # assert
    assert_response :redirect
    assert_equal I18n.t("lucid_backoffice.action_done"), flash[:notice]
  end

  def test_failed_action_does_not_render_the_secret
    # arrange
    configure_actions
    failure = Struct.new(:type) { def failure? = true }.new(:last_owner)
    secret_action(SECRET, outcome: failure)
    account = create_account

    # act
    submit(account)

    # assert
    assert_response :unprocessable_entity
    refute_includes response.body, SECRET
    assert_equal "teacher", account.reload.role
  end

  def test_new_with_a_preview_issues_a_nonce_for_secret_actions
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    get "#{ACTIONS}/issue_link/new", params: { record_id: account.id, fields: { role: "coordinator" } }, headers: as(1)

    # assert
    assert_predicate dom.at_css("input[type=hidden][name=nonce]")["value"].to_s, :present?
  end

  def test_new_without_a_preview_issues_no_nonce
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    get "#{ACTIONS}/issue_link/new", params: { record_id: account.id }, headers: as(1)

    # assert
    assert_nil dom.at_css("input[name=nonce]")
  end

  def test_replaying_the_same_post_does_not_run_again_nor_show_the_secret
    # arrange
    configure_actions
    secret_action
    account = create_account
    submit(account)
    account.reload.update!(role: "teacher")

    # act
    post "#{ACTIONS}/issue_link", params: @last_params, headers: as(1)

    # assert
    assert_response :redirect
    assert_includes response.location, "/backoffice/actions/issue_link/new"
    assert_equal I18n.t("lucid_backoffice.action_replayed"), flash[:alert]
    assert_equal "teacher", account.reload.role
    refute_includes response.body, SECRET
    assert_equal 1, events("backoffice.action.issue_link").size
  end

  def test_post_without_a_nonce_does_not_run
    # arrange
    configure_actions
    secret_action
    account = create_account
    submit(account)
    account.reload.update!(role: "teacher")

    # act
    post "#{ACTIONS}/issue_link", params: @last_params.except(:nonce), headers: as(1)

    # assert
    assert_response :redirect
    assert_equal I18n.t("lucid_backoffice.action_replayed"), flash[:alert]
    assert_equal "teacher", account.reload.role
  end

  def test_post_with_a_forged_nonce_does_not_run
    # arrange
    configure_actions
    secret_action
    account = create_account
    submit(account)
    account.reload.update!(role: "teacher")

    # act
    post "#{ACTIONS}/issue_link", params: @last_params.merge(nonce: "forjado"), headers: as(1)

    # assert
    assert_response :redirect
    assert_equal I18n.t("lucid_backoffice.action_replayed"), flash[:alert]
    assert_equal "teacher", account.reload.role
  end

  def test_nonce_of_another_action_is_not_accepted
    # arrange
    configure_actions
    secret_action
    other = define_action("OtherLink") do
      on :accounts
      field :role, :select, choices: -> { %w[teacher coordinator director] }
      perform do
        record.update!(role: role)
        record.id
      end
      secret { |_value| "outro" }
    end
    account = create_account
    get "#{ACTIONS}/issue_link/new", params: { record_id: account.id, fields: { role: "coordinator" } }, headers: as(1)
    nonce = dom.at_css("input[name=nonce]")["value"]
    snapshot = dom.at_css("input[name=snapshot]")["value"]

    # act
    post "#{ACTIONS}/#{other.key}", params: { record_id: account.id, fields: { role: "coordinator" }, snapshot: snapshot, reason: REASON, nonce: nonce },
                                    headers: as(1)

    # assert
    assert_response :redirect
    assert_equal "teacher", account.reload.role
  end

  def test_action_without_a_secret_does_not_require_a_nonce
    # arrange
    configure_actions
    plain = define_action("PlainLink") do
      on :accounts
      field :role, :select, choices: -> { %w[teacher coordinator director] }
      perform do
        record.update!(role: role)
        record.id
      end
    end
    account = create_account
    get "#{ACTIONS}/#{plain.key}/new", params: { record_id: account.id, fields: { role: "coordinator" } }, headers: as(1)
    snapshot = dom.at_css("input[name=snapshot]")["value"]

    # act
    post "#{ACTIONS}/#{plain.key}", params: { record_id: account.id, fields: { role: "coordinator" }, snapshot: snapshot, reason: REASON },
                                    headers: as(1)

    # assert
    assert_equal "coordinator", account.reload.role
    assert_equal I18n.t("lucid_backoffice.action_done"), flash[:notice]
  end

  def test_action_field_values_are_filtered_in_the_parameters_log
    # arrange
    configure_actions
    secret_action
    account = create_account

    # act
    log = capture_log { submit(account) }
    parameter_lines = log.lines.grep(/Parameters:/)

    # assert
    assert_operator parameter_lines.size, :>=, 2
    assert_includes parameter_lines.join, "[FILTERED]"
    refute_includes parameter_lines.join, "coordinator"
  end
end
