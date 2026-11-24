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
    post "#{ACTIONS}/#{key}", params: { record_id: account.id, fields: { role: "coordinator" }, snapshot: snapshot, reason: REASON },
                              headers: as(1)
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
end
