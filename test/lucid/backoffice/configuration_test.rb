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
    assert_equal :get, config.sign_out_method
    assert_includes config.categories, "public"
    assert_includes config.categories, "unclassified"
  end

  def conflict = Lucid::Backoffice::Error::ConfigurationConflict

  def test_appearance_defaults
    # arrange
    # act
    config = Lucid::Backoffice::Configuration.new

    # assert
    assert_nil config.brand_color
    assert_equal({}, config.theme)
    assert_equal :default, config.stylesheet
    assert_empty config.extra_stylesheets
  end

  def test_brand_color_accepts_hex_and_nil
    # arrange
    config = Lucid::Backoffice::Configuration.new

    # act
    config.brand_color = "#abc"
    short = config.brand_color
    config.brand_color = "#AABBCC"
    long = config.brand_color
    config.brand_color = nil

    # assert
    assert_equal "#abc", short
    assert_equal "#AABBCC", long
    assert_nil config.brand_color
  end

  def test_brand_color_rejects_invalid_values
    # arrange
    config = Lucid::Backoffice::Configuration.new
    invalid = ["red", "#ggg", "#12345", "ff0066", "#fff;}", 123, ""]

    # act
    results = invalid.map { |value| assert_raises(conflict) { config.brand_color = value }.message }

    # assert
    assert(results.all? { _1.include?("brand_color") })
    assert_nil config.brand_color
  end

  def test_theme_setter_stores_normalized_tokens
    # arrange
    config = Lucid::Backoffice::Configuration.new

    # act
    config.theme = { "bg" => "#111", radius: 4 }

    # assert
    assert_equal({ bg: "#111", radius: "4" }, config.theme)
  end

  def test_theme_setter_rejects_unknown_tokens_and_keeps_previous_value
    # arrange
    config = Lucid::Backoffice::Configuration.new
    config.theme = { bg: "#111" }

    # act
    error = assert_raises(conflict) { config.theme = { bg: "#222", nope: "1px" } }

    # assert
    assert_includes error.message, "nope"
    assert_equal({ bg: "#111" }, config.theme)
  end

  def test_theme_setter_rejects_non_hash
    # arrange
    config = Lucid::Backoffice::Configuration.new

    # act
    error = assert_raises(conflict) { config.theme = "bg" }

    # assert
    assert_includes error.message, "Hash"
  end

  def test_theme_setter_rejects_unsafe_values
    # arrange
    config = Lucid::Backoffice::Configuration.new

    # act
    # assert
    assert_raises(conflict) { config.theme = { bg: "red;}</style><script>" } }
    assert_raises(conflict) { config.theme = { bg: "url(http://x)" } }
  end

  def test_stylesheet_accepts_default_nil_path_url_and_list
    # arrange
    config = Lucid::Backoffice::Configuration.new

    # act
    config.stylesheet = "/mine.css"
    path = config.stylesheet
    config.stylesheet = ["/a.css", "https://cdn.example/b.css"]
    list = config.stylesheet
    config.stylesheet = nil
    none = config.stylesheet
    config.stylesheet = :default

    # assert
    assert_equal "/mine.css", path
    assert_equal ["/a.css", "https://cdn.example/b.css"], list
    assert_nil none
    assert_equal :default, config.stylesheet
  end

  def test_stylesheet_resets_to_default
    # arrange
    config = Lucid::Backoffice::Configuration.new
    config.stylesheet = "/mine.css"

    # act
    config.stylesheet = :default

    # assert
    assert_equal :default, config.stylesheet
  end

  def test_stylesheet_rejects_mixing_default_with_paths
    # arrange
    config = Lucid::Backoffice::Configuration.new

    # act
    error = assert_raises(conflict) { config.stylesheet = [:default, "/mine.css"] }

    # assert
    assert_includes error.message, "default"
    assert_equal :default, config.stylesheet
  end

  def test_stylesheet_rejects_bad_references
    # arrange
    config = Lucid::Backoffice::Configuration.new
    bad = ["javascript:alert(1)", "x.css", "/a b.css", "/a\"onload=x.css", "data:text/css,a{}", 5]

    # act
    # assert
    bad.each do |reference|
      assert_raises(conflict, reference.inspect) { config.stylesheet = reference }
      assert_raises(conflict, reference.inspect) { config.extra_stylesheets = [reference] }
    end
  end

  def test_extra_stylesheets_setter_wraps_single_value_and_resets
    # arrange
    config = Lucid::Backoffice::Configuration.new

    # act
    config.extra_stylesheets = "/extra.css"
    single = config.extra_stylesheets
    config.extra_stylesheets = nil

    # assert
    assert_equal ["/extra.css"], single
    assert_empty config.extra_stylesheets
  end

  def test_stylesheet_urls_for_default_replacement_and_none
    # arrange
    config = Lucid::Backoffice::Configuration.new
    config.extra_stylesheets = ["/extra.css"]

    # act
    default = config.stylesheet_urls("/gem.css")
    config.stylesheet = ["/a.css", "/b.css"]
    replaced = config.stylesheet_urls("/gem.css")
    config.stylesheet = nil
    none = config.stylesheet_urls("/gem.css")

    # assert
    assert_equal ["/gem.css", "/extra.css"], default
    assert_equal ["/a.css", "/b.css", "/extra.css"], replaced
    assert_equal ["/extra.css"], none
  end

  def test_stylesheet_rejects_protocol_relative_urls
    # arrange
    config = Lucid::Backoffice::Configuration.new
    reference = "//evil.example/x.css"

    # act
    stylesheet_error = assert_raises(conflict) { config.stylesheet = reference }
    list_error = assert_raises(conflict) { config.stylesheet = ["/ok.css", reference] }
    extra_error = assert_raises(conflict) { config.extra_stylesheets = [reference] }

    # assert
    [stylesheet_error, list_error, extra_error].each { assert_includes _1.message, reference }
    assert_equal :default, config.stylesheet
    assert_empty config.extra_stylesheets
  end
end
