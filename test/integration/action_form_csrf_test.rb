require "integration_helper"
require "action_helper"

class ActionFormCsrfIntegrationTest < PanelTest
  ACTIONS = "/backoffice/actions".freeze
  REASON = "investigar chamado 123".freeze
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

  def define_role_action
    klass = Class.new(Lucid::Backoffice::Action)
    klass.define_singleton_method(:name) { "ChangeUserRole" }
    klass.class_eval do
      on :accounts
      label "Corrigir papel"
      field :role, :select, choices: -> { %w[teacher coordinator director] }
      perform { record.update!(role: role) }
    end
  end

  def open_preview(account)
    get "#{ACTIONS}/change_user_role/new", params: { record_id: account.id, fields: { role: "coordinator" } }, headers: as(1)
  end

  def form_token = dom.at_css("form.lb-action-form input[name=authenticity_token]")&.[]("value")

  def snapshot_value = dom.at_css("form.lb-action-form input[name=snapshot]")["value"]

  def execution(account, **overrides)
    { record_id: account.id, fields: { role: "coordinator" }, snapshot: snapshot_value, reason: REASON }.merge(overrides)
  end

  def test_action_form_carries_an_authenticity_token_inside_the_form
    # arrange
    configure_actions
    define_role_action
    account = Account.create!(role: "teacher", nickname: "Mia", level: 1)

    # act
    with_forgery_protection { open_preview(account) }

    # assert
    assert_response :ok
    assert_predicate form_token, :present?
  end

  def test_post_with_the_token_read_from_the_form_is_accepted
    # arrange
    configure_actions
    define_role_action
    account = Account.create!(role: "teacher", nickname: "Mia", level: 1)

    # act
    with_forgery_protection do
      open_preview(account)
      post "#{ACTIONS}/change_user_role", params: execution(account, authenticity_token: form_token), headers: as(1)
    end

    # assert
    refute_equal 422, response.status
    assert_response :redirect
  end

  def test_post_without_the_token_is_rejected_as_forgery
    # arrange
    configure_actions
    define_role_action
    account = Account.create!(role: "teacher", nickname: "Mia", level: 1)
    open_preview(account)
    params = execution(account)

    # act
    with_forgery_protection do
      assert_raises(ActionController::InvalidAuthenticityToken) do
        post "#{ACTIONS}/change_user_role", params: params, headers: as(1)
      end
    end

    # assert
    assert_equal "teacher", account.reload.role
  end
end
