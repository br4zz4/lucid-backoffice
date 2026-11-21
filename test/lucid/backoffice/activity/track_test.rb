require "test_helper"

class ActivityTrackTest < ActivityTest
  Outcome = Struct.new(:type, :failed) do
    def failure? = failed
  end

  def track(name = "widget.created", **options, &block)
    Lucid::Backoffice::Activity.track(name, **options, &block)
  end

  def test_ok_track_records_one_event_with_subject_and_changed_fields
    # arrange
    widget = nil

    # act
    track do |tracker|
      widget = Widget.create!(label: "Secret label", quantity: 4)
      tracker.subject(widget)
    end

    # assert
    event = events.sole
    assert_equal "widget.created", event.name
    assert_equal "ok", event.outcome
    assert_equal [{ "type" => "Widget", "id" => widget.id }], event.subjects
    assert_equal %w[id label quantity created_at].sort, event.changed_fields.sort
    refute_includes event.changed_fields, "updated_at"
    refute_includes event.to_json, "Secret label"
  end

  def test_changed_fields_hold_names_only_on_update
    # arrange
    widget = Widget.create!(label: "a", quantity: 1)

    # act
    track("widget.updated") do |tracker|
      widget.update!(quantity: 2)
      tracker.subject(widget)
    end

    # assert
    assert_equal ["quantity"], events.sole.changed_fields
  end

  def test_payload_is_stored
    # arrange
    payload = { "count" => 2, "mode" => "bulk" }

    # act
    track { |tracker| tracker.payload(payload) }

    # assert
    assert_equal payload, events.sole.payload
  end

  def test_actor_and_request_come_from_current
    # arrange
    actor = Widget.create!(label: "operator")
    Lucid::Backoffice::Current.actor = actor
    Lucid::Backoffice::Current.request_id = "req-1"
    Lucid::Backoffice::Current.ip_address = "10.0.0.7"
    Lucid::Backoffice::Current.user_agent = "Agent/1.0"
    Lucid::Backoffice::Current.tenant_identifier = :escola
    Lucid::Backoffice::Current.reason = "support ticket"

    # act
    track { |_tracker| nil }

    # assert
    event = events.sole
    assert_equal "Widget", event.actor_type
    assert_equal actor.id, event.actor_id
    assert_equal "req-1", event.request_id
    assert_equal "10.0.0.7", event.ip_address.to_s
    assert_equal "Agent/1.0", event.user_agent
    assert_equal "escola", event.tenant_identifier
    assert_equal "support ticket", event.reason
  end

  def test_reason_argument_wins_over_current
    # arrange
    Lucid::Backoffice::Current.reason = "from current"

    # act
    track(reason: "explicit") { |_tracker| nil }

    # assert
    assert_equal "explicit", events.sole.reason
  end

  def test_actor_is_system_outside_a_context
    # arrange
    Lucid::Backoffice::Current.reset

    # act
    track { |_tracker| nil }

    # assert
    event = events.sole
    assert_equal "System", event.actor_type
    assert_nil event.actor_id
    assert_nil event.request_id
  end

  def test_event_lives_in_the_same_transaction
    # arrange
    widget = nil

    # act
    ActiveRecord::Base.transaction do
      track do |tracker|
        widget = Widget.create!(label: "x")
        tracker.subject(widget)
      end
      raise ActiveRecord::Rollback
    end

    # assert
    assert_equal 0, events.size
    assert_equal 0, Widget.count
  end

  def test_exception_after_track_rolls_back_the_event
    # arrange
    error = Class.new(StandardError)

    # act
    assert_raises(error) do
      ActiveRecord::Base.transaction do
        track { |tracker| tracker.subject(Widget.create!(label: "x")) }
        raise error
      end
    end

    # assert
    assert_equal 0, events.size
    assert_equal 0, Widget.count
  end

  def test_exception_in_block_records_nothing_and_propagates
    # arrange
    error = Class.new(StandardError)

    # act
    raised = assert_raises(error) do
      track do |tracker|
        tracker.subject(Widget.create!(label: "x"))
        raise error, "boom"
      end
    end

    # assert
    assert_equal "boom", raised.message
    assert_equal 0, events.size
    assert_equal 0, Widget.count
  end

  def test_failure_result_records_outcome_and_undoes_the_write
    # arrange
    result = Outcome.new(:class_full, true)

    # act
    returned = track("widget.enrolled") do |tracker|
      tracker.subject(Widget.create!(label: "x"))
      result
    end

    # assert
    assert_same result, returned
    event = events.sole
    assert_equal "class_full", event.outcome
    assert_equal "widget.enrolled", event.name
    assert_equal 0, Widget.count
  end

  def test_success_result_records_ok
    # arrange
    result = Outcome.new(:whatever, false)

    # act
    returned = track { |_tracker| result }

    # assert
    assert_same result, returned
    assert_equal "ok", events.sole.outcome
  end

  def test_block_value_is_returned
    # arrange
    expected = :value

    # act
    returned = track { |_tracker| expected }

    # assert
    assert_equal :value, returned
  end

  def test_nested_tracks_record_one_event_each_with_same_request_id
    # arrange
    Lucid::Backoffice::Current.request_id = "req-nested"

    # act
    track("outer.done") do |_outer|
      track("inner.done") { |_inner| Widget.create!(label: "x") }
    end

    # assert
    assert_equal %w[inner.done outer.done], events.map(&:name).sort
    assert_equal ["req-nested"], events.map(&:request_id).uniq
    assert_equal 1, Widget.count
  end

  def test_nested_failure_does_not_remove_the_outer_event
    # arrange
    failing = Outcome.new(:nope, true)

    # act
    track("outer.done") do |_outer|
      track("inner.done") { |_inner| failing }
      Widget.create!(label: "kept")
    end

    # assert
    outcomes = events.to_h { |event| [event.name, event.outcome] }
    assert_equal({ "inner.done" => "nope", "outer.done" => "ok" }, outcomes)
    assert_equal 1, Widget.count
  end

  def test_event_write_failure_undoes_the_write_and_propagates
    # arrange
    invalid_payload = { "email" => "maria@example.com" }

    # act
    assert_raises(ActiveRecord::RecordInvalid) do
      track do |tracker|
        tracker.subject(Widget.create!(label: "x"))
        tracker.payload(invalid_payload)
      end
    end

    # assert
    assert_equal 0, events.size
    assert_equal 0, Widget.count
  end
end
