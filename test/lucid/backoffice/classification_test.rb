require "test_helper"

class ClassificationTest < BackofficeTest
  def test_id_is_public_by_convention
    # arrange
    configure_minimal

    # act
    category = Lucid::Backoffice::Classification.category_for("students", "id")

    # assert
    assert_equal "public", category
  end

  def test_foreign_key_suffix_is_public_by_convention
    # arrange
    configure_minimal

    # act
    category = Lucid::Backoffice::Classification.category_for("enrollments", "student_id")

    # assert
    assert_equal "public", category
  end

  def test_polymorphic_type_suffix_is_public_by_convention
    # arrange
    configure_minimal

    # act
    category = Lucid::Backoffice::Classification.category_for("notes", "owner_type")

    # assert
    assert_equal "public", category
  end

  def test_timestamps_are_public_by_convention
    # arrange
    configure_minimal

    # act
    created = Lucid::Backoffice::Classification.category_for("students", "created_at")
    updated = Lucid::Backoffice::Classification.category_for("students", "updated_at")

    # assert
    assert_equal "public", created
    assert_equal "public", updated
  end

  def test_similar_names_are_not_public_by_convention
    # arrange
    configure_minimal

    # act
    categories = %w[valid paid_at identity createdat].map { |column| Lucid::Backoffice::Classification.category_for("students", column) }

    # assert
    assert_equal %w[unclassified], categories.uniq
  end

  def test_yaml_classifies_by_table_and_column
    # arrange
    path = write_yaml("students:\n  cpf: documents\n  phone: contact\n")

    # act
    configure_minimal { |config| config.classification_path = path }

    # assert
    assert_equal "documents", Lucid::Backoffice::Classification.category_for("students", "cpf")
    assert_equal "contact", Lucid::Backoffice::Classification.category_for("students", "phone")
  end

  def test_same_column_in_another_table_is_not_classified
    # arrange
    path = write_yaml("students:\n  cpf: documents\n")

    # act
    configure_minimal { |config| config.classification_path = path }

    # assert
    assert_equal "unclassified", Lucid::Backoffice::Classification.category_for("guardians", "cpf")
  end

  def test_accepts_symbols_for_table_and_column
    # arrange
    path = write_yaml("students:\n  cpf: documents\n")
    configure_minimal { |config| config.classification_path = path }

    # act
    category = Lucid::Backoffice::Classification.category_for(:students, :cpf)

    # assert
    assert_equal "documents", category
  end

  def test_unlisted_column_defaults_to_unclassified
    # arrange
    path = write_yaml("students:\n  cpf: documents\n")
    configure_minimal { |config| config.classification_path = path }

    # act
    category = Lucid::Backoffice::Classification.category_for("students", "nickname")

    # assert
    assert_equal "unclassified", category
  end

  def test_defaults_to_unclassified_without_a_classification_path
    # arrange
    configure_minimal

    # act
    category = Lucid::Backoffice::Classification.category_for("students", "cpf")

    # assert
    assert_equal "unclassified", category
  end

  def test_convention_wins_over_yaml
    # arrange
    path = write_yaml("students:\n  id: documents\n")
    configure_minimal { |config| config.classification_path = path }

    # act
    category = Lucid::Backoffice::Classification.category_for("students", "id")

    # assert
    assert_equal "public", category
  end

  def test_table_with_empty_columns_is_accepted
    # arrange
    path = write_yaml("students:\n")

    # act
    configure_minimal { |config| config.classification_path = path }

    # assert
    assert_equal "unclassified", Lucid::Backoffice::Classification.category_for("students", "cpf")
  end

  def test_reset_forgets_loaded_entries
    # arrange
    path = write_yaml("students:\n  cpf: documents\n")
    configure_minimal { |config| config.classification_path = path }

    # act
    Lucid::Backoffice::Classification.reset!
    Lucid::Backoffice.configuration.classification_path = nil
    category = Lucid::Backoffice::Classification.category_for("students", "cpf")

    # assert
    assert_equal "unclassified", category
  end

  def test_reset_configuration_clears_classification
    # arrange
    path = write_yaml("students:\n  cpf: documents\n")
    configure_minimal { |config| config.classification_path = path }

    # act
    Lucid::Backoffice.reset_configuration!

    # assert
    assert_equal "unclassified", Lucid::Backoffice::Classification.category_for("students", "cpf")
  end
end
