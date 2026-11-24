require "integration_helper"

class AssetsForgeryProtectionIntegrationTest < PanelTest
  CONTROLLER_FILE = Lucid::Backoffice::Engine.root.join("app/controllers/lucid/backoffice/assets_controller.rb").to_s

  def setup
    super
    Rails.application.eager_load!
    @original_forgery_protection = ActionController::Base.allow_forgery_protection
    @original_strategy = ActionController::Base.forgery_protection_strategy
    @original_callbacks = [ActionController::Base, *ActionController::Base.descendants].to_h { |klass| [klass, klass.__callbacks] }
    ActionController::Base.allow_forgery_protection = true
    ActionController::Base.protect_from_forgery with: :exception
    reload_assets_controller
  end

  def teardown
    @original_callbacks.each { |klass, callbacks| klass.__callbacks = callbacks }
    ActionController::Base.forgery_protection_strategy = @original_strategy
    reload_assets_controller
    ActionController::Base.allow_forgery_protection = @original_forgery_protection
    super
  end

  def reload_assets_controller
    Lucid::Backoffice.send(:remove_const, :AssetsController)
    load CONTROLLER_FILE
  end

  def test_javascript_is_served_with_forgery_protection_on_and_no_xhr_header
    # arrange
    path = "/backoffice/assets/lucid_backoffice.js?v=#{Lucid::Backoffice::VERSION}"

    # act
    get path

    # assert
    assert_response :ok
    assert_includes response.media_type, "text/javascript"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.body, "data-lb-reason-form"
  end

  def test_stylesheet_is_served_with_forgery_protection_on
    # arrange
    path = "/backoffice/assets/lucid_backoffice.css?v=#{Lucid::Backoffice::VERSION}"

    # act
    get path

    # assert
    assert_response :ok
    assert_includes response.media_type, "text/css"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  def test_theme_stylesheet_is_served_with_forgery_protection_on
    # arrange
    path = "/backoffice/assets/theme.css?v=#{Lucid::Backoffice::Theme.digest}"

    # act
    get path

    # assert
    assert_response :ok
    assert_includes response.media_type, "text/css"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end
end
