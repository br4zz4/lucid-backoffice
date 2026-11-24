require "data_helper"

class RevealTest < DataTest
  Reveal = Lucid::Backoffice::Reveal
  Records = Lucid::Backoffice::Records
  Operator = Struct.new(:id)
  include ActiveSupport::Testing::TimeHelpers

  REASON = "support ticket 1234".freeze

  def setup
    super
    Reveal.delete_all
    Lucid::Backoffice::Current.reset
    Lucid::Backoffice::Activity::Event.unscoped.delete_all
  end

  def teardown
    travel_back
    Lucid::Backoffice::Current.reset
    super
  end

  def allow_all
    configure_minimal { |config| config.authorize = ->(*) { true } }
  end

  def events(name)
    Lucid::Backoffice::Activity::Event.where(name: name).order(:id).to_a
  end

  def grant(operator, category: "contact", reason: REASON, tenant: nil)
    Reveal.grant(operator: operator, category: category, reason: reason, tenant: tenant)
  end

  def test_grant_without_permission_is_forbidden_and_creates_nothing
    # arrange
    configure_minimal

    # act
    assert_raises(Lucid::Backoffice::Error::Forbidden) { grant(Operator.new(1)) }

    # assert
    assert_equal 0, Reveal.count
    assert_equal 0, events("backoffice.reveal.grant").size
  end

  def test_grant_asks_for_the_reveal_permission_with_tenant_and_category
    # arrange
    received = nil
    configure_minimal do |config|
      config.authorize = lambda { |*args|
        received = args
        true
      }
    end
    operator = Operator.new(1)

    # act
    grant(operator, category: "contact", tenant: "school_a")

    # assert
    assert_equal [operator, :reveal, { tenant: "school_a", category: "contact" }], received
  end

  def test_blank_reason_is_invalid_and_reveals_nothing
    # arrange
    allow_all
    operator = Operator.new(1)

    # act
    assert_raises(ActiveRecord::RecordInvalid) { grant(operator, reason: "   ") }

    # assert
    assert_equal 0, Reveal.count
    assert_empty Reveal.categories_for(operator: operator)
    assert_equal 0, events("backoffice.reveal.grant").size
  end

  def test_empty_reason_is_invalid
    # arrange
    allow_all

    # act and assert
    assert_raises(ActiveRecord::RecordInvalid) { grant(Operator.new(1), reason: "") }
    assert_equal 0, Reveal.count
  end

  def test_reason_with_fewer_than_ten_characters_is_invalid
    # arrange
    allow_all
    operator = Operator.new(1)

    # act
    error = assert_raises(ActiveRecord::RecordInvalid) { grant(operator, reason: "123456789") }

    # assert
    assert error.record.errors[:reason].any?
    assert_equal 0, Reveal.count
    assert_empty Reveal.categories_for(operator: operator)
  end

  def test_reason_with_exactly_ten_characters_is_valid
    # arrange
    allow_all

    # act
    reveal = grant(Operator.new(1), reason: "1234567890")

    # assert
    assert reveal.persisted?
  end

  def test_unknown_category_is_invalid_and_creates_nothing
    # arrange
    allow_all

    # act
    error = assert_raises(ActiveRecord::RecordInvalid) { grant(Operator.new(1), category: "nonexistent") }

    # assert
    assert error.record.errors[:category].any?
    assert_equal 0, Reveal.count
  end

  def test_grant_records_the_reveal_with_the_configured_duration
    # arrange
    allow_all
    Lucid::Backoffice.configuration.reveal_duration = 600
    operator = Operator.new(7)
    now = Time.utc(2026, 1, 1, 12, 0, 0)

    # act
    reveal = travel_to(now) { grant(operator, category: "documents", tenant: "school_a") }

    # assert
    assert_equal "RevealTest::Operator", reveal.operator_type
    assert_equal 7, reveal.operator_id
    assert_equal "documents", reveal.category
    assert_equal "school_a", reveal.tenant_identifier
    assert_equal REASON, reveal.reason
    assert_equal now + 600, reveal.expires_at
    assert_nil reveal.revoked_at
  end

  def test_grant_records_the_grant_event_with_category_and_reason_and_no_data
    # arrange
    allow_all
    operator = Operator.new(3)

    # act
    grant(operator, category: "financial", reason: "  audit 2026 review  ")

    # assert
    event = events("backoffice.reveal.grant").sole
    assert_equal({ "category" => "financial" }, event.payload)
    assert_equal "audit 2026 review", event.reason
    assert_equal "RevealTest::Operator", event.actor_type
    assert_equal 3, event.actor_id
  end

  def test_categories_for_returns_the_active_categories_of_the_operator
    # arrange
    allow_all
    operator = Operator.new(1)
    grant(operator, category: "contact")
    grant(operator, category: "documents")
    grant(operator, category: "contact")

    # act
    categories = Reveal.categories_for(operator: operator)

    # assert
    assert_equal %w[contact documents], categories.sort
  end

  def test_categories_for_nil_operator_is_empty
    # arrange
    allow_all
    grant(Operator.new(1))

    # act and assert
    assert_empty Reveal.categories_for(operator: nil)
  end

  def test_categories_for_isolates_by_operator
    # arrange
    allow_all
    operator_a = Operator.new(1)
    operator_b = Operator.new(2)
    grant(operator_b, category: "contact")

    # act
    seen_by_a = Reveal.categories_for(operator: operator_a)
    seen_by_b = Reveal.categories_for(operator: operator_b)

    # assert
    assert_empty seen_by_a
    assert_equal ["contact"], seen_by_b
  end

  def test_categories_for_isolates_by_operator_type
    # arrange
    allow_all
    other_class = Struct.new(:id)
    grant(Operator.new(1))

    # act
    categories = Reveal.categories_for(operator: other_class.new(1))

    # assert
    assert_empty categories
  end

  def test_categories_for_isolates_by_tenant_identifier
    # arrange
    allow_all
    operator = Operator.new(1)
    grant(operator, category: "contact", tenant: "school_a")

    # act
    in_a = Reveal.categories_for(operator: operator, tenant: "school_a")
    in_b = Reveal.categories_for(operator: operator, tenant: "school_b")
    shared = Reveal.categories_for(operator: operator)

    # assert
    assert_equal ["contact"], in_a
    assert_empty in_b
    assert_empty shared
  end

  def test_categories_for_isolates_by_category
    # arrange
    allow_all
    operator = Operator.new(1)
    grant(operator, category: "contact")

    # act
    categories = Reveal.categories_for(operator: operator)

    # assert
    assert_includes categories, "contact"
    refute_includes categories, "documents"
  end

  def test_tenant_object_is_resolved_through_the_adapter
    # arrange
    allow_all
    operator = Operator.new(1)
    adapter = Object.new
    adapter.define_singleton_method(:identifier) { |tenant| "id_#{tenant}" }
    Lucid::Backoffice::Tenancy.stub(:adapter, adapter) do
      # act
      reveal = grant(operator, tenant: 42)

      # assert
      assert_equal "id_42", reveal.tenant_identifier
      assert_equal ["contact"], Reveal.categories_for(operator: operator, tenant: 42)
    end
  end

  def test_reveal_expires_after_the_configured_duration
    # arrange
    allow_all
    Lucid::Backoffice.configuration.reveal_duration = 900
    operator = Operator.new(1)
    start = Time.utc(2026, 1, 1, 12, 0, 0)
    travel_to(start) { grant(operator) }

    # act
    before_deadline = travel_to(start + 899) { Reveal.categories_for(operator: operator) }
    at_deadline = travel_to(start + 900) { Reveal.categories_for(operator: operator) }
    after_deadline = travel_to(start + 901) { Reveal.categories_for(operator: operator) }

    # assert
    assert_equal ["contact"], before_deadline
    assert_empty at_deadline
    assert_empty after_deadline
  end

  def test_revoke_ends_the_reveal_immediately
    # arrange
    allow_all
    operator = Operator.new(1)
    reveal = grant(operator)
    assert_equal ["contact"], Reveal.categories_for(operator: operator)

    # act
    Reveal.revoke(reveal, operator: operator)

    # assert
    assert_empty Reveal.categories_for(operator: operator)
    refute reveal.reload.active?
    refute_nil reveal.revoked_at
  end

  def test_revoke_records_the_revoke_event
    # arrange
    allow_all
    operator = Operator.new(1)
    reveal = grant(operator, category: "documents")

    # act
    Reveal.revoke(reveal, operator: operator)

    # assert
    event = events("backoffice.reveal.revoke").sole
    assert_equal({ "category" => "documents" }, event.payload)
    assert_equal 1, event.actor_id
  end

  def test_revoke_is_idempotent_and_keeps_the_first_revoked_at
    # arrange
    allow_all
    operator = Operator.new(1)
    reveal = grant(operator)
    first = Time.utc(2026, 1, 1, 12, 0, 0)
    travel_to(first) { Reveal.revoke(reveal, operator: operator) }

    # act
    travel_to(first + 60) { Reveal.revoke(reveal, operator: operator) }

    # assert
    assert_equal first, reveal.reload.revoked_at
    assert_empty Reveal.categories_for(operator: operator)
  end

  def test_revoke_requires_the_reveal_permission
    # arrange
    allow_all
    operator = Operator.new(1)
    reveal = grant(operator)
    Lucid::Backoffice.configuration.authorize = ->(*) { false }

    # act
    assert_raises(Lucid::Backoffice::Error::Forbidden) { Reveal.revoke(reveal, operator: operator) }

    # assert
    assert_nil reveal.reload.revoked_at
    assert_equal 0, events("backoffice.reveal.revoke").size
  end

  def grant_all(operator, reason: REASON, tenant: nil)
    Reveal.grant_all(operator: operator, tenant: tenant, reason: reason)
  end

  def revealable
    Lucid::Backoffice.configuration.categories - ["public"]
  end

  def deny_categories(*denied)
    configure_minimal do |config|
      config.authorize = ->(_operator, _permission, context) { !denied.include?(context[:category]) }
    end
  end

  def test_grant_all_creates_one_reveal_per_revealable_category
    # arrange
    allow_all
    operator = Operator.new(1)

    # act
    reveals = grant_all(operator, tenant: "school_a")

    # assert
    assert_equal revealable.sort, reveals.map(&:category).sort
    assert_equal revealable.size, Reveal.count
    assert reveals.all?(&:persisted?)
    assert_equal ["school_a"], reveals.map(&:tenant_identifier).uniq
    assert_equal [REASON], reveals.map(&:reason).uniq
    assert_equal revealable.sort, Reveal.categories_for(operator: operator, tenant: "school_a").sort
    refute_includes Reveal.categories_for(operator: operator, tenant: "school_a"), "public"
  end

  def test_grant_all_records_one_grant_event_per_category_with_the_same_reason
    # arrange
    allow_all
    operator = Operator.new(3)

    # act
    grant_all(operator)

    # assert
    recorded = events("backoffice.reveal.grant")
    assert_equal revealable.size, recorded.size
    assert_equal revealable.sort, recorded.map { |event| event.payload["category"] }.sort
    assert_equal [REASON], recorded.map(&:reason).uniq
    assert_equal [3], recorded.map(&:actor_id).uniq
  end

  def test_grant_all_validates_the_reason_once_and_creates_nothing
    # arrange
    allow_all

    # act
    error = assert_raises(ActiveRecord::RecordInvalid) { grant_all(Operator.new(1), reason: "curto") }

    # assert
    assert error.record.errors[:reason].any?
    assert_equal 0, Reveal.count
    assert_equal 0, events("backoffice.reveal.grant").size
  end

  def test_grant_all_with_blank_reason_creates_nothing
    # arrange
    allow_all

    # act
    assert_raises(ActiveRecord::RecordInvalid) { grant_all(Operator.new(1), reason: "   ") }

    # assert
    assert_equal 0, Reveal.count
    assert_equal 0, events("backoffice.reveal.grant").size
  end

  def test_grant_all_skips_denied_categories
    # arrange
    deny_categories("financial", "minors")
    operator = Operator.new(1)

    # act
    reveals = grant_all(operator)

    # assert
    expected = revealable - %w[financial minors]
    assert_equal expected.sort, reveals.map(&:category).sort
    assert_equal expected.size, Reveal.count
    assert_equal expected.size, events("backoffice.reveal.grant").size
    assert_equal expected.sort, Reveal.categories_for(operator: operator).sort
  end

  def test_grant_all_asks_permission_per_revealable_category_with_tenant
    # arrange
    asked = []
    configure_minimal do |config|
      config.authorize = lambda { |operator, permission, context|
        asked << [permission, context]
        true
      }
    end

    # act
    grant_all(Operator.new(1), tenant: "school_a")

    # assert
    assert_equal revealable.map { |category| [:reveal, { tenant: "school_a", category: category }] }.sort_by { |_, c| c[:category] },
                 asked.select { |permission, _| permission == :reveal }.uniq.sort_by { |_, c| c[:category] }
  end

  def test_grant_all_with_every_category_denied_is_forbidden_and_creates_nothing
    # arrange
    configure_minimal { |config| config.authorize = ->(*) { false } }

    # act
    assert_raises(Lucid::Backoffice::Error::Forbidden) { grant_all(Operator.new(1)) }

    # assert
    assert_equal 0, Reveal.count
    assert_equal 0, events("backoffice.reveal.grant").size
  end

  def test_grant_all_is_atomic_when_a_later_step_fails
    # arrange
    allow_all
    calls = 0
    failing = lambda do |_event|
      calls += 1
      raise "boom" if calls == 3
    end
    Lucid::Backoffice::Activity::Event.set_callback(:create, :before, failing)

    # act
    begin
      assert_raises(StandardError) { grant_all(Operator.new(1)) }
    ensure
      Lucid::Backoffice::Activity::Event.skip_callback(:create, :before, failing)
    end

    # assert
    assert_equal 0, Reveal.count
    assert_equal 0, events("backoffice.reveal.grant").size
  end

  def test_grant_all_is_scoped_to_the_tenant
    # arrange
    allow_all
    operator = Operator.new(1)

    # act
    grant_all(operator, tenant: "school_a")

    # assert
    assert_equal revealable.sort, Reveal.categories_for(operator: operator, tenant: "school_a").sort
    assert_empty Reveal.categories_for(operator: operator, tenant: "school_b")
    assert_empty Reveal.categories_for(operator: operator)
  end

  def test_revoke_all_revokes_every_active_reveal_of_the_operator_in_the_tenant
    # arrange
    allow_all
    operator = Operator.new(1)
    grant_all(operator, tenant: "school_a")

    # act
    Reveal.revoke_all(operator: operator, tenant: "school_a")

    # assert
    assert_empty Reveal.categories_for(operator: operator, tenant: "school_a")
    assert Reveal.all.all? { |reveal| reveal.reload.revoked_at }
  end

  def test_revoke_all_records_one_revoke_event_per_category
    # arrange
    allow_all
    operator = Operator.new(1)
    grant_all(operator)

    # act
    Reveal.revoke_all(operator: operator)

    # assert
    recorded = events("backoffice.reveal.revoke")
    assert_equal revealable.sort, recorded.map { |event| event.payload["category"] }.sort
    assert_equal [1], recorded.map(&:actor_id).uniq
  end

  def test_revoke_all_does_not_touch_another_tenant
    # arrange
    allow_all
    operator = Operator.new(1)
    grant_all(operator, tenant: "school_a")
    grant_all(operator, tenant: "school_b")

    # act
    Reveal.revoke_all(operator: operator, tenant: "school_a")

    # assert
    assert_empty Reveal.categories_for(operator: operator, tenant: "school_a")
    assert_equal revealable.sort, Reveal.categories_for(operator: operator, tenant: "school_b").sort
    assert_equal revealable.size, events("backoffice.reveal.revoke").size
  end

  def test_revoke_all_does_not_touch_another_operator
    # arrange
    allow_all
    operator_a = Operator.new(1)
    operator_b = Operator.new(2)
    grant_all(operator_a)
    grant_all(operator_b)

    # act
    Reveal.revoke_all(operator: operator_a)

    # assert
    assert_empty Reveal.categories_for(operator: operator_a)
    assert_equal revealable.sort, Reveal.categories_for(operator: operator_b).sort
  end

  def test_revoke_all_without_active_reveals_records_nothing
    # arrange
    allow_all

    # act
    Reveal.revoke_all(operator: Operator.new(1))

    # assert
    assert_equal 0, events("backoffice.reveal.revoke").size
  end

  def test_operator_a_does_not_see_the_reveal_of_operator_b_in_records
    # arrange
    write_classification("students:\n  email: contact\n")
    Lucid::Backoffice.configuration.authorize = ->(*) { true }
    insert_student
    operator_a = Operator.new(1)
    operator_b = Operator.new(2)
    grant(operator_b, category: "contact")

    # act
    row_a = Records.list(schema: "public", table: "students", revealed: Reveal.categories_for(operator: operator_a)).rows.first
    row_b = Records.list(schema: "public", table: "students", revealed: Reveal.categories_for(operator: operator_b)).rows.first

    # assert
    assert cell(row_a, "email").masked
    assert_equal "•••••", cell(row_a, "email").value
    refute cell(row_b, "email").masked
    assert_equal "maria@example.com", cell(row_b, "email").value
  end

  def test_records_list_opens_only_the_revealed_category_in_the_revealed_tenant
    # arrange
    write_classification("students:\n  email: contact\n  cpf: documents\n")
    Lucid::Backoffice.configuration.authorize = ->(*) { true }
    insert_student
    operator = Operator.new(1)
    grant(operator, category: "contact", tenant: "school_a")

    # act
    in_a = Records.list(schema: "public", table: "students",
                        revealed: Reveal.categories_for(operator: operator, tenant: "school_a")).rows.first
    in_b = Records.list(schema: "public", table: "students",
                        revealed: Reveal.categories_for(operator: operator, tenant: "school_b")).rows.first

    # assert
    assert_equal "maria@example.com", cell(in_a, "email").value
    assert_equal "•••••", cell(in_a, "cpf").value
    assert cell(in_a, "cpf").masked
    assert_equal "•••••", cell(in_b, "email").value
    assert cell(in_b, "email").masked
  end

  def test_records_list_masks_again_after_expiry
    # arrange
    write_classification("students:\n  email: contact\n")
    Lucid::Backoffice.configuration.authorize = ->(*) { true }
    insert_student
    operator = Operator.new(1)
    start = Time.utc(2026, 1, 1, 12, 0, 0)
    travel_to(start) { grant(operator) }

    # act
    row = travel_to(start + Lucid::Backoffice.configuration.reveal_duration + 1) do
      Records.list(schema: "public", table: "students", revealed: Reveal.categories_for(operator: operator)).rows.first
    end

    # assert
    assert cell(row, "email").masked
  end
end
