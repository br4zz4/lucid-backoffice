require "test_helper"

class ConfigurationTest < BackofficeTest
  def test_configure_fails_without_current_operator
    # arrange
    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) do
      Lucid::Backoffice.configure { |config| config.authenticate = ->(_request) { true } }
    end

    # assert
    assert_includes error.message, "current_operator"
  end

  def test_configure_fails_without_authenticate
    # arrange
    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) do
      Lucid::Backoffice.configure { |config| config.current_operator = ->(_request) { :operator } }
    end

    # assert
    assert_includes error.message, "authenticate"
  end

  def test_configure_fails_when_current_operator_is_not_callable
    # arrange
    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) do
      Lucid::Backoffice.configure do |config|
        config.current_operator = :operator
        config.authenticate = ->(_request) { true }
      end
    end

    # assert
    assert_includes error.message, "current_operator"
  end

  def test_configure_returns_configuration_when_valid
    # arrange
    # act
    result = configure_minimal

    # assert
    assert_same Lucid::Backoffice.configuration, result
  end

  def test_authorize_denies_everything_by_default
    # arrange
    configure_minimal

    # act
    allowed = Lucid::Backoffice.configuration.authorize.call(:operator, :browse, nil)

    # assert
    assert_equal false, allowed
  end

  def test_authorize_accepts_a_callable
    # arrange
    configure_minimal { |config| config.authorize = ->(_operator, permission, _context) { permission == :browse } }

    # act
    allowed = Lucid::Backoffice.configuration.authorize.call(:operator, :browse, nil)
    denied = Lucid::Backoffice.configuration.authorize.call(:operator, :reveal, nil)

    # assert
    assert_equal true, allowed
    assert_equal false, denied
  end

  def test_authorize_rejects_a_non_callable
    # arrange
    config = Lucid::Backoffice::Configuration.new

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { config.authorize = "allow" }

    # assert
    assert_includes error.message, "authorize"
  end

  def test_configure_fails_when_classification_path_does_not_exist
    # arrange
    missing = File.join(Dir.mktmpdir, "missing.yml")

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) do
      configure_minimal { |config| config.classification_path = missing }
    end

    # assert
    assert_includes error.message, "classification_path"
  end

  def test_configure_fails_when_categories_lack_public
    # arrange
    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) do
      configure_minimal { |config| config.categories = %w[contact unclassified] }
    end

    # assert
    assert_includes error.message, "categories"
  end

  def test_configure_fails_when_categories_lack_unclassified
    # arrange
    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) do
      configure_minimal { |config| config.categories = %w[public contact] }
    end

    # assert
    assert_includes error.message, "categories"
  end

  def test_configure_fails_naming_the_key_of_an_unknown_category_in_the_yaml
    # arrange
    path = write_yaml("students:\n  cpf: documentos\n")

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) do
      configure_minimal { |config| config.classification_path = path }
    end

    # assert
    assert_includes error.message, "students.cpf"
  end

  def test_configure_accepts_a_custom_category_present_in_the_yaml
    # arrange
    path = write_yaml("students:\n  cpf: documentos\n")

    # act
    configure_minimal do |config|
      config.categories = %w[public documentos unclassified]
      config.classification_path = path
    end

    # assert
    assert_equal "documentos", Lucid::Backoffice::Classification.category_for("students", "cpf")
  end

  def test_defaults
    # arrange
    # act
    config = Lucid::Backoffice::Configuration.new

    # assert
    assert_equal :none, config.tenancy
    assert_equal 25, config.page_size
    assert_includes config.categories, "public"
    assert_includes config.categories, "unclassified"
  end
end
