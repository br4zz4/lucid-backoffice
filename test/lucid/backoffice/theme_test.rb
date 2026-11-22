require "test_helper"

class ThemeTest < BackofficeTest
  Theme = Lucid::Backoffice::Theme

  def conflict = Lucid::Backoffice::Error::ConfigurationConflict

  def test_defaults_are_black_with_a_lime_accent
    # arrange
    # act
    tokens = Theme.tokens(Lucid::Backoffice::Configuration.new)

    # assert
    assert_equal "#000", tokens[:bg]
    assert_equal "#c6ff00", tokens[:accent]
    assert_equal "#000", tokens[:on_accent]
    assert_equal Theme::DEFAULTS, tokens
    assert_equal Theme::DEFAULTS.keys, Theme::TOKENS
  end

  def test_brand_color_sets_accent_and_contrast
    # arrange
    config = Lucid::Backoffice::Configuration.new
    config.brand_color = "#3300cc"

    # act
    tokens = Theme.tokens(config)

    # assert
    assert_equal "#3300cc", tokens[:accent]
    assert_equal "#fff", tokens[:on_accent]
  end

  def test_theme_overrides_come_after_brand_color
    # arrange
    config = Lucid::Backoffice::Configuration.new
    config.brand_color = "#ff0066"
    config.theme = { accent: "#123456", on_accent: "#eee", radius: "2px" }

    # act
    tokens = Theme.tokens(config)

    # assert
    assert_equal "#123456", tokens[:accent]
    assert_equal "#eee", tokens[:on_accent]
    assert_equal "2px", tokens[:radius]
    assert_equal "#000", tokens[:bg]
  end

  def test_css_declares_every_token_as_custom_property
    # arrange
    config = Lucid::Backoffice::Configuration.new
    config.theme = { font_sans: "Arial, sans-serif" }

    # act
    css = Theme.css(config)

    # assert
    assert css.start_with?(".lb{")
    assert_includes css, "--lb-bg:#000"
    assert_includes css, "--lb-on-accent:#000"
    assert_includes css, "--lb-font-sans:Arial, sans-serif"
    assert_equal Theme::TOKENS.size, css.scan("--lb-").size
  end

  def test_digest_is_stable_and_changes_with_configuration
    # arrange
    first = Lucid::Backoffice::Configuration.new
    same = Lucid::Backoffice::Configuration.new
    branded = Lucid::Backoffice::Configuration.new
    branded.brand_color = "#ff0066"
    themed = Lucid::Backoffice::Configuration.new
    themed.theme = { radius: "0" }

    # act
    digests = [first, same, branded, themed].map { Theme.digest(_1) }

    # assert
    assert_equal digests[0], digests[1]
    assert_equal 3, digests.uniq.size
    assert_match(/\A\h{12}\z/, digests[0])
  end

  def test_tokens_default_to_the_global_configuration
    # arrange
    configure_minimal { |config| config.brand_color = "#ff0066" }

    # act
    tokens = Theme.tokens

    # assert
    assert_equal "#ff0066", tokens[:accent]
    assert_equal Theme.css(Lucid::Backoffice.configuration), Theme.css
  end

  def test_contrast_for
    # arrange
    cases = { "#c6ff00" => "#000", "#000" => "#fff", "#000000" => "#fff", "#fff" => "#000", "#ffffff" => "#000",
              "#ff0066" => "#000", "#3300cc" => "#fff", "#0a0" => "#000", "#123" => "#fff", "#FFF" => "#000" }

    # act
    results = cases.keys.to_h { [_1, Theme.contrast_for(_1)] }

    # assert
    assert_equal cases, results
  end

  def test_validate_token_accepts_plain_values
    # arrange
    values = { bg: "#111", border: "rgb(255 255 255 / .1)", radius: "12px", font_sans: '"Inter Variable", Inter, sans-serif', text: "red" }

    # act
    # assert
    values.each { |token, value| assert_nil Theme.validate_token!(token, value) }
  end

  def test_validate_token_rejects_unknown_token
    # arrange
    # act
    error = assert_raises(conflict) { Theme.validate_token!(:nope, "1px") }

    # assert
    assert_includes error.message, "nope"
    assert_raises(conflict) { Theme.validate_token!("bg", "#000") }
  end

  def test_validate_token_rejects_injection_attempts
    # arrange
    attacks = ["red;}</style><script>", "url(http://x)", "URL(http://x)", "red; color: blue", "a{b:c}", "<script>", "expression(alert(1))",
               "@import 'x'", "javascript:alert(1)", "a\\", "", nil]

    # act
    # assert
    attacks.each { |value| assert_raises(conflict, value.inspect) { Theme.validate_token!(:bg, value) } }
  end

  def test_validate_color
    # arrange
    # act
    # assert
    ["#fff", "#FFFFFF", "#c6ff00"].each { assert_nil Theme.validate_color!(_1) }
    ["fff", "#ffff", "red", nil, :red, "#fff;", "#fff}"].each { |value| assert_raises(conflict, value.inspect) { Theme.validate_color!(value) } }
  end

  def test_validate_token_rejects_line_breaks_and_tabs
    # arrange
    values = ["red\nblue", "red\r\nblue", "red\tblue", "\nred"]

    # act
    # assert
    values.each { |value| assert_raises(conflict, value.inspect) { Theme.validate_token!(:bg, value) } }
  end
end
