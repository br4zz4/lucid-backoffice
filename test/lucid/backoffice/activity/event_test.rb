require "test_helper"

class ActivityEventTest < ActivityTest
  def test_payload_accepts_identifiers
    # arrange
    payload = { "count" => 3, "none" => nil, "flag" => true, "off" => false, "ids" => [1, 2, 3], "kind" => "reveal.read_only/x_y" }
    event = build_event(payload: payload)

    # act
    valid = event.valid?

    # assert
    assert valid, event.errors.full_messages.to_s
  end

  def test_payload_refuses_values_that_are_not_identifiers
    # arrange
    values = ["Maria Silva", "123.456.789-09", "maria@example.com", "Maria", "has space", "abc123", "a-b", "", 1.5, { "a" => 1 }, [1, "x"]]

    # act
    results = values.map { |value| build_event(payload: { "field" => value }) }

    # assert
    results.each_with_index do |event, index|
      refute event.valid?, "expected #{values[index].inspect} to be refused"
      assert event.errors[:payload].any?
    end
  end

  def test_valid_event_is_persisted
    # arrange
    event = build_event(payload: { "count" => 1 })

    # act
    saved = event.save

    # assert
    assert saved
    assert_equal 1, events.size
  end

  def test_persisted_event_is_readonly
    # arrange
    event = build_event
    event.save!

    # act
    readonly = event.readonly?
    error = assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(name: "other") }

    # assert
    assert readonly
    assert_kind_of ActiveRecord::ReadOnlyRecord, error
    assert_equal "widget.created", event.reload.name
  end

  def test_persisted_event_cannot_be_destroyed
    # arrange
    event = build_event
    event.save!

    # act
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy }

    # assert
    assert_equal 1, events.size
  end

  def test_requires_name_actor_type_and_occurred_at
    # arrange
    event = Lucid::Backoffice::Activity::Event.new

    # act
    event.valid?

    # assert
    %i[name actor_type occurred_at].each { |attribute| assert event.errors[attribute].any?, "#{attribute} should be required" }
  end
end
