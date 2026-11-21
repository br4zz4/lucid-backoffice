require "test_helper"
require "active_job"
require "global_id"
require "lucid/backoffice/integrations/active_job"

GlobalID.app = "lucid-backoffice-test"

class Widget
  include GlobalID::Identification
end

class RecordingJob < ActiveJob::Base
  cattr_accessor :seen

  def perform
    self.class.seen = {
      actor: Lucid::Backoffice::Current.actor,
      request_id: Lucid::Backoffice::Current.request_id
    }
    Lucid::Backoffice::Activity.record(name: "job.ran")
  end
end

class ActiveJobIntegrationTest < IntegrationTest
  include ActiveJob::TestHelper

  def setup
    super
    ActiveJob::Base.queue_adapter = :test
    RecordingJob.seen = nil
  end

  def test_job_runs_with_actor_and_request_id_of_the_enqueuer
    # arrange
    operator = Widget.create!(label: "operator")
    Lucid::Backoffice::Current.actor = operator
    Lucid::Backoffice::Current.request_id = "req-job"
    RecordingJob.perform_later
    Lucid::Backoffice::Current.reset

    # act
    perform_enqueued_jobs

    # assert
    assert_equal operator, RecordingJob.seen[:actor]
    assert_equal "req-job", RecordingJob.seen[:request_id]
    assert_equal "Widget", events.first.actor_type
    assert_equal operator.id, events.first.actor_id
  end

  def test_job_without_actor_runs_as_system
    # arrange
    RecordingJob.perform_later

    # act
    perform_enqueued_jobs

    # assert
    assert_nil RecordingJob.seen[:actor]
    assert_equal "System", events.first.actor_type
  end

  def test_current_is_restored_after_perform_now
    # arrange
    outer = Widget.create!(label: "outer")
    Lucid::Backoffice::Current.actor = outer
    Lucid::Backoffice::Current.request_id = "outer-req"

    # act
    RecordingJob.perform_now

    # assert
    assert_equal outer, Lucid::Backoffice::Current.actor
    assert_equal "outer-req", Lucid::Backoffice::Current.request_id
  end
end
