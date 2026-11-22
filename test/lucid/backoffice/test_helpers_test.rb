require "test_helper"
require "lucid/backoffice/test_helpers"

class TestHelpersTest < BackofficeTest
  include Lucid::Backoffice::TestHelpers

  Operator = Struct.new(:id)
  Mask = Lucid::Backoffice::Mask
  Reveal = Lucid::Backoffice::Reveal

  def setup
    super
    Reveal.delete_all
  end

  def teardown
    Reveal.delete_all
    super
  end

  def test_with_operator_returns_the_operator
    # arrange
    operator = Operator.new(1)

    # act
    result = with_operator(operator)

    # assert
    assert_same operator, result
  end

  def test_with_operator_configures_current_operator_and_authenticate
    # arrange
    operator = Operator.new(1)

    # act
    with_operator(operator)

    # assert
    config = Lucid::Backoffice.configuration
    assert_same operator, config.current_operator.call(:controller)
    assert config.authenticate.call(:controller)
  end

  def test_with_operator_allows_only_the_given_permissions
    # arrange
    operator = Operator.new(1)

    # act
    with_operator(operator, permissions: %i[browse reveal])

    # assert
    authorize = Lucid::Backoffice.configuration.authorize
    assert authorize.call(operator, :browse, {})
    assert authorize.call(operator, :reveal, {})
    refute authorize.call(operator, :view_activity, {})
  end

  def test_with_operator_without_permissions_denies_everything
    # arrange
    operator = Operator.new(1)

    # act
    with_operator(operator)

    # assert
    refute Lucid::Backoffice.configuration.authorize.call(operator, :browse, {})
  end

  def test_grant_reveal_creates_an_active_reveal
    # arrange
    operator = Operator.new(7)

    # act
    reveal = grant_reveal(operator: operator, category: :contact, tenant: "acme")

    # assert
    assert reveal.persisted?
    assert_equal "TestHelpersTest::Operator", reveal.operator_type
    assert_equal 7, reveal.operator_id
    assert_equal "acme", reveal.tenant_identifier
    assert_equal "contact", reveal.category
    assert_includes Reveal.active, reveal
  end

  def test_grant_reveal_is_isolated_by_operator
    # arrange
    grant_reveal(operator: Operator.new(1), category: :contact, tenant: "acme")

    # act
    other = Reveal.categories_for(operator: Operator.new(2), tenant: "acme")

    # assert
    assert_empty other
    assert_equal ["contact"], Reveal.categories_for(operator: Operator.new(1), tenant: "acme")
  end

  def test_grant_reveal_is_isolated_by_tenant
    # arrange
    grant_reveal(operator: Operator.new(1), category: :contact, tenant: "acme")

    # act
    other = Reveal.categories_for(operator: Operator.new(1), tenant: "globex")

    # assert
    assert_empty other
    assert_empty Reveal.categories_for(operator: Operator.new(1))
  end

  def test_grant_reveal_is_isolated_by_category
    # arrange
    operator = Operator.new(1)
    grant_reveal(operator: operator, category: :contact, tenant: "acme")

    # act
    categories = Reveal.categories_for(operator: operator, tenant: "acme")

    # assert
    assert_equal ["contact"], categories
    refute_includes categories, "documents"
  end

  def test_grant_reveal_without_tenant_has_no_tenant_identifier
    # arrange
    # act
    reveal = grant_reveal(operator: Operator.new(1), category: :documents)

    # assert
    assert_nil reveal.tenant_identifier
  end

  def test_grant_reveal_expires_after_the_reveal_duration
    # arrange
    configure_minimal { |config| config.reveal_duration = 5.minutes }
    started = Time.current

    # act
    reveal = grant_reveal(operator: Operator.new(1), category: :contact)

    # assert
    assert_in_delta started + 5.minutes, reveal.expires_at, 5
  end

  def test_assert_masked_accepts_each_mask
    # arrange
    masks = [Mask::EMPTY, Mask::TEXT, Mask::TIME, Mask::NUMBER, "[texto, 120 caracteres]"]

    # act
    # assert
    masks.each { |mask| assert_masked(mask) }
  end

  def test_assert_masked_rejects_a_real_value
    # arrange
    # act
    error = assert_raises(Minitest::Assertion) { assert_masked("maria@example.com") }

    # assert
    assert_match(/expected "maria@example.com" to be masked/, error.message)
  end

  def test_assert_masked_rejects_a_look_alike_text_mask
    # arrange
    # act
    # assert
    assert_raises(Minitest::Assertion) { assert_masked("[texto, abc caracteres]") }
  end

  def test_assert_masked_uses_the_given_message
    # arrange
    # act
    error = assert_raises(Minitest::Assertion) { assert_masked("secret", "leaked") }

    # assert
    assert_equal "leaked", error.message
  end
end
