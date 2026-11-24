require "test_helper"

class MailTest < BackofficeTest
  Mail = Lucid::Backoffice::Mail

  def setup
    super
    @previous_mailer = Object.const_defined?(:ActionMailer) ? Object.send(:remove_const, :ActionMailer) : nil
  end

  def teardown
    Object.send(:remove_const, :ActionMailer) if Object.const_defined?(:ActionMailer)
    Object.const_set(:ActionMailer, @previous_mailer) if @previous_mailer
    super
  end

  def install_action_mailer(delivery_method: :smtp, smtp_settings: {}, perform_deliveries: true, registered: %i[smtp test file sendmail])
    base = Class.new do
      class << self
        attr_accessor :delivery_method, :smtp_settings, :perform_deliveries, :delivery_methods
      end
    end
    base.delivery_method = delivery_method
    base.smtp_settings = smtp_settings
    base.perform_deliveries = perform_deliveries
    base.delivery_methods = registered.to_h { |name| [name, Object] }
    Object.const_set(:ActionMailer, Module.new)
    ActionMailer.const_set(:Base, base)
    base
  end

  def test_unavailable_without_action_mailer
    # arrange
    refute Object.const_defined?(:ActionMailer)

    # act
    available = Mail.available?

    # assert
    refute available
  end

  def test_smtp_with_a_remote_address_is_available
    # arrange
    install_action_mailer(smtp_settings: { address: "smtp.sendgrid.net", port: 587 })

    # act
    available = Mail.available?

    # assert
    assert available
  end

  def test_smtp_without_address_is_unavailable
    # arrange
    install_action_mailer(smtp_settings: { port: 587 })

    # act
    available = Mail.available?

    # assert
    refute available
  end

  def test_smtp_with_a_blank_address_is_unavailable
    # arrange
    install_action_mailer(smtp_settings: { address: "  " })

    # act
    available = Mail.available?

    # assert
    refute available
  end

  def test_smtp_with_nil_settings_is_unavailable
    # arrange
    install_action_mailer(smtp_settings: nil)

    # act
    available = Mail.available?

    # assert
    refute available
  end

  def test_smtp_pointing_to_the_local_machine_is_unavailable
    # arrange
    results = %w[localhost 127.0.0.1 ::1].map do |address|
      install_action_mailer(smtp_settings: { address: address })
      Mail.available?
    ensure
      Object.send(:remove_const, :ActionMailer)
    end

    # act
    available = results

    # assert
    assert_equal [false, false, false], available
  end

  def test_perform_deliveries_false_is_unavailable
    # arrange
    install_action_mailer(smtp_settings: { address: "smtp.sendgrid.net" }, perform_deliveries: false)

    # act
    available = Mail.available?

    # assert
    refute available
  end

  def test_registered_non_smtp_delivery_methods_are_available
    # arrange
    results = %i[test file sendmail].map do |method|
      install_action_mailer(delivery_method: method)
      Mail.available?
    ensure
      Object.send(:remove_const, :ActionMailer)
    end

    # act
    available = results

    # assert
    assert_equal [true, true, true], available
  end

  def test_custom_registered_delivery_method_is_available
    # arrange
    install_action_mailer(delivery_method: :postmark, registered: %i[smtp postmark])

    # act
    available = Mail.available?

    # assert
    assert available
  end

  def test_unregistered_delivery_method_is_unavailable
    # arrange
    install_action_mailer(delivery_method: :ghost)

    # act
    available = Mail.available?

    # assert
    refute available
  end

  def test_configuration_reads_the_action_mailer_by_default
    # arrange
    install_action_mailer(smtp_settings: { address: "smtp.sendgrid.net" })

    # act
    available = Lucid::Backoffice.configuration.email_available?

    # assert
    assert available
  end

  def test_configuration_override_wins_over_a_configured_action_mailer
    # arrange
    install_action_mailer(smtp_settings: { address: "smtp.sendgrid.net" })
    configure_minimal { |config| config.email_available = -> { false } }

    # act
    available = Lucid::Backoffice.configuration.email_available?

    # assert
    refute available
  end

  def test_configuration_override_wins_over_an_unconfigured_action_mailer
    # arrange
    configure_minimal { |config| config.email_available = -> { true } }

    # act
    available = Lucid::Backoffice.configuration.email_available?

    # assert
    assert available
  end

  def test_configuration_override_result_is_coerced_to_a_boolean
    # arrange
    configure_minimal { |config| config.email_available = -> { "yes" } }

    # act
    available = Lucid::Backoffice.configuration.email_available?

    # assert
    assert_same true, available
  end

  def test_configuration_without_override_is_false_without_action_mailer
    # arrange
    configure_minimal

    # act
    available = Lucid::Backoffice.configuration.email_available?

    # assert
    assert_same false, available
  end

  def test_action_reads_email_available_from_the_configuration
    # arrange
    configure_minimal { |config| config.email_available = -> { true } }
    action_class = Class.new(Lucid::Backoffice::Action)

    # act
    available = action_class.new.email_available?

    # assert
    assert available
  end
end
