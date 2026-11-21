require "test_helper"

class AuthorizationTest < BackofficeTest
  Authorization = Lucid::Backoffice::Authorization
  Operator = Struct.new(:id)

  def test_denies_everything_by_default
    # arrange
    operator = Operator.new(1)

    # act
    results = Authorization::PERMISSIONS.map { |permission| Authorization.allowed?(operator, permission) }

    # assert
    assert_equal Authorization::PERMISSIONS.size, results.size
    assert results.none?
  end

  def test_authorize_receives_operator_permission_symbol_and_context
    # arrange
    operator = Operator.new(1)
    received = nil
    configure_minimal { |config| config.authorize = ->(*args) { received = args } }
    context = { tenant: "school_a", category: "contact" }

    # act
    Authorization.allowed?(operator, "reveal", context)

    # assert
    assert_equal [operator, :reveal, context], received
    assert_instance_of Symbol, received[1]
  end

  def test_allowed_follows_the_configured_answer
    # arrange
    operator = Operator.new(1)
    configure_minimal { |config| config.authorize = ->(_operator, permission, _context) { permission == :browse } }

    # act and assert
    assert Authorization.allowed?(operator, :browse)
    refute Authorization.allowed?(operator, :reveal)
  end

  def test_truthy_non_boolean_answers_are_true
    # arrange
    configure_minimal { |config| config.authorize = ->(*) { "yes" } }

    # act and assert
    assert_equal true, Authorization.allowed?(Operator.new(1), :browse)
  end

  def test_nil_operator_is_denied_without_calling_authorize
    # arrange
    called = false
    configure_minimal { |config| config.authorize = ->(*) { called = true } }

    # act
    result = Authorization.allowed?(nil, :browse)

    # assert
    assert_equal false, result
    refute called
  end

  def test_authorize_bang_raises_forbidden_by_default
    # arrange
    operator = Operator.new(1)

    # act
    error = assert_raises(Lucid::Backoffice::Error::Forbidden) { Authorization.authorize!(operator, :reveal) }

    # assert
    assert_kind_of Lucid::Backoffice::Error, error
    assert_match(/reveal/, error.message)
  end

  def test_authorize_bang_raises_for_nil_operator_even_if_authorize_allows
    # arrange
    configure_minimal { |config| config.authorize = ->(*) { true } }

    # act and assert
    assert_raises(Lucid::Backoffice::Error::Forbidden) { Authorization.authorize!(nil, :browse) }
  end

  def test_authorize_bang_returns_true_when_allowed
    # arrange
    configure_minimal { |config| config.authorize = ->(*) { true } }

    # act
    result = Authorization.authorize!(Operator.new(1), :browse)

    # assert
    assert_equal true, result
  end
end
