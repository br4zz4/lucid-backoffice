require "test_helper"
require "lucid/case"
require "lucid/backoffice/integrations/lucid_case"

module Widgets
  class Create < Lucid::Case::Command
    attributes :label

    def call!
      success(widget: Widget.create!(label: label, quantity: 1))
    end
  end

  class Update < Lucid::Case::Command
    attributes :widget, :label

    def call!
      widget.update!(label: label)
      success(widget: widget)
    end
  end

  class CreateWithPayload < Lucid::Case::Command
    attributes :label, :name

    def activity_payload
      { name: name }
    end

    def call!
      success(widget: Widget.create!(label: label))
    end
  end

  class CreateWithIds < Lucid::Case::Command
    attributes :label

    def activity_payload
      { plan_id: 7 }
    end

    def call!
      success(widget: Widget.create!(label: label))
    end
  end

  class CreateThenFail < Lucid::Case::Command
    attributes :label

    def call!
      Widget.create!(label: label)
      failure(:last_owner)
    end
  end

  class CreateThenGuard < Lucid::Case::Command
    attributes :label

    fail_if :blocked?

    def call!
      success(widget: Widget.create!(label: label))
    end

    private

    def blocked? = true
  end

  class CreateThenRaise < Lucid::Case::Command
    attributes :label

    def call!
      Widget.create!(label: label)
      raise ArgumentError, "boom"
    end
  end

  class Silent < Lucid::Case::Command
    events :disabled
    attributes :label

    def call!
      success(widget: Widget.create!(label: label))
    end
  end

  class Outer < Lucid::Case::Command
    attributes :label

    def call!
      inner = Widgets::Create.call(label: label)
      success(widget: inner[:widget])
    end
  end

  class Find < Lucid::Case::Query
    attributes :label

    def call!
      success(widget: Widget.find_by(label: label))
    end
  end
end

class LucidCaseIntegrationTest < IntegrationTest
  def test_records_one_event_named_after_the_command
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    Widgets::Create.call(label: "a")

    # assert
    assert_equal ["widgets.create"], events.map(&:name)
    assert_equal "ok", events.first.outcome
  end

  def test_records_subjects_in_attributes_and_in_result_content
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!
    existing = Widget.create!(label: "old")

    # act
    result = Widgets::Update.call(widget: existing, label: "new")

    # assert
    assert result.success?
    assert_equal [{ "type" => "Widget", "id" => existing.id }], events.first.subjects
  end

  def test_records_subject_created_by_the_command
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    result = Widgets::Create.call(label: "a")

    # assert
    assert_equal [{ "type" => "Widget", "id" => result[:widget].id }], events.first.subjects
  end

  def test_changed_fields_are_names_without_values_and_without_updated_at
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!
    existing = Widget.create!(label: "old")

    # act
    Widgets::Update.call(widget: existing, label: "secret-new")

    # assert
    assert_equal ["label"], events.first.changed_fields
    refute_includes events.first.attributes.values.map(&:to_s).join, "secret-new"
  end

  def test_takes_actor_and_request_from_current
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!
    operator = Widget.create!(label: "operator")
    Lucid::Backoffice::Current.actor = operator
    Lucid::Backoffice::Current.request_id = "req-1"

    # act
    Widgets::Create.call(label: "a")

    # assert
    assert_equal "Widget", events.first.actor_type
    assert_equal operator.id, events.first.actor_id
    assert_equal "req-1", events.first.request_id
  end

  def test_event_is_written_inside_the_command_transaction
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    error = assert_raises(ActiveRecord::RecordInvalid) { Widgets::CreateWithPayload.call(label: "a", name: "Maria") }

    # assert
    assert_match(/payload/i, error.message)
    assert_equal 0, Widget.count
    assert_equal 0, events.size
  end

  def test_failure_records_event_with_type_as_outcome_after_rollback
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    result = Widgets::CreateThenFail.call(label: "a")

    # assert
    assert result.failure?
    assert_equal 0, Widget.count
    assert_equal ["last_owner"], events.map(&:outcome)
    assert_equal ["widgets.create_then_fail"], events.map(&:name)
  end

  def test_guard_failure_records_event_with_guard_type_after_rollback
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    result = Widgets::CreateThenGuard.call(label: "a")

    # assert
    assert result.failure?
    assert_equal 0, Widget.count
    assert_equal ["blocked"], events.map(&:outcome)
  end

  def test_exception_records_nothing_and_propagates
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    assert_raises(ArgumentError) { Widgets::CreateThenRaise.call(label: "a") }

    # assert
    assert_equal 0, Widget.count
    assert_equal 0, events.size
  end

  def test_nested_commands_record_one_event_each_with_the_same_request_id
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!
    Lucid::Backoffice::Current.request_id = "req-nested"

    # act
    Widgets::Outer.call(label: "a")

    # assert
    assert_equal ["widgets.create", "widgets.outer"], events.map(&:name).sort
    assert_equal ["req-nested"], events.map(&:request_id).uniq
  end

  def test_command_with_events_disabled_records_nothing
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    Widgets::Silent.call(label: "a")

    # assert
    assert_equal 1, Widget.count
    assert_equal 0, events.size
  end

  def test_records_even_with_case_events_recording_disabled
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!
    Lucid::Case.configuration.events.recording = :disabled

    # act
    Widgets::Create.call(label: "a")

    # assert
    assert_equal ["widgets.create"], events.map(&:name)
  end

  def test_records_activity_payload_with_identifiers
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    Widgets::CreateWithIds.call(label: "a")

    # assert
    assert_equal({ "plan_id" => 7 }, events.first.payload)
  end

  def test_query_records_nothing
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!
    Widget.create!(label: "a")

    # act
    Widgets::Find.call(label: "a")

    # assert
    assert_equal 0, events.size
  end

  def test_install_is_idempotent
    # arrange
    Lucid::Backoffice::Integrations::LucidCase.install!
    Lucid::Backoffice::Integrations::LucidCase.install!

    # act
    Widgets::Create.call(label: "a")

    # assert
    assert_equal 1, events.size
  end
end
