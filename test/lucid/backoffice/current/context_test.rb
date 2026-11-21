require "test_helper"

class CurrentContextTest < ActivityTest
  Actor = Struct.new(:id)

  class ProbeController < ActionController::Base
    include Lucid::Backoffice::Context

    def index
      self.class.seen = {
        actor: Lucid::Backoffice::Current.actor, request_id: Lucid::Backoffice::Current.request_id,
        ip_address: Lucid::Backoffice::Current.ip_address, user_agent: Lucid::Backoffice::Current.user_agent
      }
      head :ok
    end

    class << self
      attr_accessor :seen
    end
  end

  def call_probe
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "203.0.113.9", "HTTP_USER_AGENT" => "Probe/2.0", "action_dispatch.request_id" => "req-abc")
    ProbeController.action(:index).call(env)
    ProbeController.seen
  end

  def test_current_resets
    # arrange
    Lucid::Backoffice::Current.actor = :someone
    Lucid::Backoffice::Current.request_id = "r"
    Lucid::Backoffice::Current.reason = "why"

    # act
    Lucid::Backoffice::Current.reset

    # assert
    assert_nil Lucid::Backoffice::Current.actor
    assert_nil Lucid::Backoffice::Current.request_id
    assert_nil Lucid::Backoffice::Current.reason
  end

  def test_context_fills_actor_and_request_from_current_actor
    # arrange
    actor = Actor.new(7)
    configure_minimal { |config| config.current_actor = ->(_controller) { actor } }

    # act
    seen = call_probe

    # assert
    assert_same actor, seen[:actor]
    assert_equal "req-abc", seen[:request_id]
    assert_equal "203.0.113.9", seen[:ip_address]
    assert_equal "Probe/2.0", seen[:user_agent]
  end

  def test_context_falls_back_to_current_operator
    # arrange
    configure_minimal { |config| config.current_operator = ->(_controller) { :fallback_operator } }

    # act
    seen = call_probe

    # assert
    assert_equal :fallback_operator, seen[:actor]
  end

  def test_current_actor_wins_over_current_operator
    # arrange
    configure_minimal do |config|
      config.current_operator = ->(_controller) { :operator }
      config.current_actor = ->(_controller) { :actor }
    end

    # act
    seen = call_probe

    # assert
    assert_equal :actor, seen[:actor]
  end

  def test_actor_is_nil_without_any_resolver
    # arrange
    Lucid::Backoffice.reset_configuration!

    # act
    seen = call_probe

    # assert
    assert_nil seen[:actor]
  end
end
