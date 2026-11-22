require "test_helper"
require "impersonation_app_helper"

class ImpersonationMaskTest < BackofficeTest
  include ImpersonationSupport
  include ImpersonationAppSupport
  include Lucid::Backoffice::TestHelpers

  BIRTHDATE = Date.new(2015, 6, 20)

  def setup
    super
    reset_app_data
    configure_impersonation
    configure_classification
    @operator = create_operator
  end

  def teardown
    reset_app_data
    super
  end

  def impersonate(tenant: "alfa")
    Lucid::Backoffice::Current.impersonation_id = 1
    Lucid::Backoffice::Current.actor = @operator
    Lucid::Backoffice::Current.tenant_identifier = tenant
  end

  def create_student(**attributes)
    Student.create!({ name: "Maria Silva", birthdate: BIRTHDATE, status: "active", cpf: "123.456.789-00", age: 9 }.merge(attributes))
  end

  def test_impersonating_is_false_by_default
    # arrange
    Lucid::Backoffice::Current.reset

    # act
    result = Lucid::Backoffice.impersonating?

    # assert
    refute result
  end

  def test_impersonating_is_true_with_an_impersonation_id
    # arrange
    impersonate

    # act
    result = Lucid::Backoffice.impersonating?

    # assert
    assert result
  end

  def test_impersonating_is_false_after_reset
    # arrange
    impersonate

    # act
    Lucid::Backoffice::Current.reset

    # assert
    refute Lucid::Backoffice.impersonating?
  end

  def test_text_becomes_dots
    # arrange
    student = create_student
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    assert_equal "•••••", found.name
    assert_equal "•••••", found.cpf
  end

  def test_date_becomes_first_of_january_of_the_year
    # arrange
    student = create_student
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    assert_equal Date.new(2015, 1, 1), found.birthdate
  end

  def test_public_and_integer_values_are_intact
    # arrange
    student = create_student
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    assert_equal "active", found.status
    assert_equal 9, found.age
    assert_equal student.id, found.id
  end

  def test_nil_values_stay_nil
    # arrange
    student = create_student(name: nil, birthdate: nil, cpf: nil)
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    assert_nil found.name
    assert_nil found.birthdate
    assert_nil found.cpf
  end

  def test_masked_record_is_readonly
    # arrange
    student = create_student
    impersonate
    found = Student.find(student.id)

    # act
    error = assert_raises(ActiveRecord::ReadOnlyRecord) { found.save! }

    # assert
    assert_kind_of ActiveRecord::ReadOnlyRecord, error
    assert found.readonly?
  end

  def test_masked_record_cannot_be_updated_or_destroyed
    # arrange
    student = create_student
    impersonate
    found = Student.find(student.id)

    # act
    update = -> { found.update!(status: "x") }
    destroy = -> { found.destroy! }

    # assert
    assert_raises(ActiveRecord::ReadOnlyRecord, &update)
    assert_raises(ActiveRecord::ReadOnlyRecord, &destroy)
    Lucid::Backoffice::Current.reset
    assert_equal "Maria Silva", Student.find(student.id).name
  end

  def test_masked_record_has_no_dirty_changes
    # arrange
    student = create_student
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    refute found.changed?
    assert_empty found.changes
  end

  def test_revealed_category_passes_only_that_category
    # arrange
    student = create_student
    grant_reveal(operator: @operator, category: "contact", tenant: "alfa")
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    assert_equal "Maria Silva", found.name
    assert_equal "•••••", found.cpf
    assert_equal Date.new(2015, 1, 1), found.birthdate
  end

  def test_reveal_granted_through_reveal_grant_is_honored
    # arrange
    student = create_student
    Lucid::Backoffice.configuration.authorize = ->(_operator, permission, _context) { permission == :reveal }
    Lucid::Backoffice::Reveal.grant(operator: @operator, category: "documents", reason: "investigar chamado 4321", tenant: "alfa")
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    assert_equal "123.456.789-00", found.cpf
    assert_equal "•••••", found.name
  end

  def test_revealed_record_stays_readonly
    # arrange
    student = create_student
    grant_reveal(operator: @operator, category: "contact", tenant: "alfa")
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    assert found.readonly?
  end

  def test_reveal_in_another_tenant_does_not_apply
    # arrange
    student = create_student
    grant_reveal(operator: @operator, category: "contact", tenant: "beta")
    impersonate(tenant: "alfa")

    # act
    found = Student.find(student.id)

    # assert
    assert_equal "•••••", found.name
  end

  def test_reveal_of_another_operator_does_not_apply
    # arrange
    student = create_student
    grant_reveal(operator: create_operator("outro"), category: "contact", tenant: "alfa")
    impersonate

    # act
    found = Student.find(student.id)

    # assert
    assert_equal "•••••", found.name
  end

  def test_revealed_categories_are_loaded_once_per_request
    # arrange
    student = create_student
    grant_reveal(operator: @operator, category: "contact", tenant: "alfa")
    impersonate
    Student.find(student.id)

    # act
    categories = Lucid::Backoffice::Current.revealed_categories

    # assert
    assert_equal ["contact"], categories
  end

  def test_backoffice_tables_are_never_masked
    # arrange
    reveal = grant_reveal(operator: @operator, category: "contact", tenant: "alfa", reason: "motivo do teste")
    impersonate

    # act
    found = BackofficeReveal.find(reveal.id)

    # assert
    assert_equal "motivo do teste", found.reason
    refute found.readonly?
  end

  def test_model_marked_unmasked_is_never_masked
    # arrange
    student = create_student
    impersonate

    # act
    found = UnmaskedStudent.find(student.id)

    # assert
    assert_equal "Maria Silva", found.name
    assert_equal BIRTHDATE, found.birthdate
    refute found.readonly?
  end

  def test_outside_impersonation_nothing_is_masked
    # arrange
    student = create_student
    Lucid::Backoffice::Current.reset

    # act
    found = Student.find(student.id)

    # assert
    assert_equal "Maria Silva", found.name
    assert_equal BIRTHDATE, found.birthdate
    assert_equal "123.456.789-00", found.cpf
  end

  def test_outside_impersonation_records_are_writable
    # arrange
    student = create_student
    Lucid::Backoffice::Current.reset
    found = Student.find(student.id)

    # act
    found.update!(status: "inactive")

    # assert
    refute found.readonly?
    assert_equal "inactive", Student.find(student.id).status
  end
end
