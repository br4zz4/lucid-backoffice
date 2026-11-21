require "test_helper"

class MaskTest < BackofficeTest
  def mask(value, type, category: "contact", revealed: false)
    Lucid::Backoffice::Mask.call(value: value, category: category, column_type: type, revealed: revealed)
  end

  def test_public_value_passes_through
    # arrange
    value = "Maria"

    # act
    result = mask(value, :string, category: "public")

    # assert
    assert_equal "Maria", result
  end

  def test_revealed_value_passes_through
    # arrange
    value = "Maria"

    # act
    result = mask(value, :string, revealed: true)

    # assert
    assert_equal "Maria", result
  end

  def test_public_nil_passes_through
    # arrange
    # act
    result = mask(nil, :string, category: "public")

    # assert
    assert_nil result
  end

  def test_nil_becomes_dash
    # arrange
    # act
    result = mask(nil, :string)

    # assert
    assert_equal "—", result
  end

  def test_long_text_shows_only_its_length
    # arrange
    value = "a" * 41

    # act
    result = mask(value, :text)

    # assert
    assert_equal "[texto, 41 caracteres]", result
  end

  def test_text_of_exactly_forty_characters_is_short
    # arrange
    value = "a" * 40

    # act
    result = mask(value, :text)

    # assert
    assert_equal "•••••", result
  end

  def test_short_text_is_fully_masked
    # arrange
    value = "Maria"

    # act
    result = mask(value, :string)

    # assert
    assert_equal "•••••", result
  end

  def test_date_is_masked_as_a_date
    # arrange
    value = Date.new(2020, 1, 2)

    # act
    result = mask(value, :date)

    # assert
    assert_equal "••/••/••••", result
  end

  def test_datetime_is_masked_as_a_date
    # arrange
    value = Time.utc(2020, 1, 2, 3, 4, 5)

    # act
    result = mask(value, :datetime)

    # assert
    assert_equal "••/••/••••", result
  end

  def test_integer_is_masked_as_a_number
    # arrange
    value = 42

    # act
    result = mask(value, :integer)

    # assert
    assert_equal "•••", result
  end

  def test_boolean_is_masked_as_a_number
    # arrange
    value = false

    # act
    result = mask(value, :boolean)

    # assert
    assert_equal "•••", result
  end

  def test_masked_output_never_contains_the_original_value
    # arrange
    value = "segredo"

    # act
    result = mask(value, :string)

    # assert
    refute_includes result, value
  end
end
