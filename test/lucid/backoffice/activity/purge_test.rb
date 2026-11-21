require "test_helper"

class ActivityPurgeTest < ActivityTest
  NOW = Time.utc(2026, 11, 21, 12, 0, 0)

  def retention
    Lucid::Backoffice.configuration.activity_retention
  end

  def seed_event(age)
    build_event(occurred_at: NOW - age).tap(&:save!)
  end

  def purge
    Lucid::Backoffice::Activity::Purge.call(now: NOW)
  end

  def test_deletes_only_events_older_than_retention_and_returns_count
    # arrange
    old = [seed_event(retention + 1.day), seed_event(retention + 1.hour)]
    recent = [seed_event(retention - 1.day), seed_event(1.minute)]

    # act
    removed = purge

    # assert
    assert_equal 2, removed
    assert_equal recent.map(&:id).sort, events.map(&:id).sort
    assert_empty(Lucid::Backoffice::Activity::Event.where(id: old.map(&:id)))
  end

  def test_returns_zero_when_nothing_is_old
    # arrange
    seed_event(1.day)

    # act
    removed = purge

    # assert
    assert_equal 0, removed
    assert_equal 1, events.size
  end

  def test_event_exactly_at_cutoff_is_kept
    # arrange
    seed_event(retention)

    # act
    removed = purge

    # assert
    assert_equal 0, removed
  end

  def test_deletes_in_batches_of_activity_purge_batch
    # arrange
    Lucid::Backoffice.configuration.activity_purge_batch = 2
    5.times { seed_event(retention + 1.day) }
    kept = seed_event(1.day)
    batches = []
    original = Lucid::Backoffice::Activity::Event.method(:unscoped)
    counter = lambda do |*args, &block|
      relation = original.call(*args, &block)
      batches << true
      relation
    end

    # act
    removed = Lucid::Backoffice::Activity::Event.stub(:unscoped, counter) { purge }

    # assert
    assert_equal 5, removed
    assert_equal 3, batches.size
    assert_equal [kept.id], events.map(&:id)
  end

  def test_respects_custom_retention
    # arrange
    Lucid::Backoffice.configuration.activity_retention = 1.day
    seed_event(2.days)
    keep = seed_event(1.hour)

    # act
    removed = purge

    # assert
    assert_equal 1, removed
    assert_equal [keep.id], events.map(&:id)
  end
end
