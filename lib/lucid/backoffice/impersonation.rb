module Lucid
  module Backoffice
    # An operator seeing the app as one of its users: read-only, masked, time-boxed, with a reason, and every
    # step recorded. The app supplies how to find and sign in the user (see +config.impersonation+).
    class Impersonation < ActiveRecord::Base
      self.table_name = "lucid_backoffice_impersonations"

      PURPOSE = :lucid_backoffice_impersonation
      TOKEN_TTL = 60.seconds

      validates :operator_type, :operator_id, :user_id, :expires_at, :started_at, presence: true
      validate :reason_long_enough, on: :create

      scope :active, -> { where(ended_at: nil).where("expires_at > ?", Time.current) }

      class << self
        # Starts an impersonation and returns it with the one-time entry URL.
        #
        # @raise [Error::Forbidden] the operator may not impersonate
        # @raise [ActiveRecord::RecordInvalid] the reason is too short
        # @raise [Records::NotFound] the user does not exist in the tenant
        def start(operator:, user_id:, reason:, tenant: nil, metadata: {})
          Authorization.authorize!(operator, :impersonate, { tenant: tenant, user_id: user_id })
          config = Lucid::Backoffice.configuration.impersonation
          user = config.find_user.call(tenant, user_id) or raise Records::NotFound, "no such user"
          transaction do
            active.where(operator_type: operator.class.name, operator_id: operator.id).find_each { |previous| previous.end!(reason: "replaced") }
            impersonation = create!(operator_type: operator.class.name, operator_id: operator.id, tenant_identifier: Reveal.tenant_identifier(tenant),
                                    user_type: user.class.name, user_id: user.id, reason: reason.to_s.strip, metadata: metadata,
                                    started_at: Time.current, expires_at: Time.current + config.duration)
            Current.impersonation_id = impersonation.id
            Activity.record(name: "backoffice.impersonation.start", reason: impersonation.reason, actor: operator)
            [impersonation, entry_url(impersonation, tenant)]
          end
        end

        # Consumes the one-time token: marks the entry and returns the impersonation.
        # @raise [Records::NotFound] the token is invalid, expired, reused or for another tenant
        def enter(token, tenant_identifier: nil)
          id = verifier.verify(token, purpose: PURPOSE)
          impersonation = lock.find_by(id: id)
          valid = impersonation && impersonation.entered_at.nil? && impersonation.active? &&
                  (tenant_identifier.nil? || impersonation.tenant_identifier == tenant_identifier.to_s)
          raise Records::NotFound, "invalid token" unless valid

          impersonation.update!(entered_at: Time.current)
          impersonation
        rescue ActiveSupport::MessageVerifier::InvalidSignature
          raise Records::NotFound, "invalid token"
        end

        def active_for(user:)
          active.where(user_type: user.class.name, user_id: user.id).order(:id).last
        end

        def entry_url(impersonation, tenant)
          token = verifier.generate(impersonation.id, purpose: PURPOSE, expires_in: TOKEN_TTL)
          base = Lucid::Backoffice.configuration.impersonation.entry_url&.call(tenant).to_s
          "#{base}/lucid_backoffice/impersonation/enter?token=#{CGI.escape(token)}"
        end

        def verifier
          Rails.application.message_verifier(PURPOSE)
        end

        def lock
          where(nil)
        end
      end

      def active?
        ended_at.nil? && expires_at > Time.current
      end

      # Ends the impersonation now. +reason+ is +manual+, +expired+, +replaced+ or +revoked+.
      def end!(reason: "manual")
        return self if ended_at

        update!(ended_at: Time.current, end_reason: reason.to_s)
        Activity.record(name: "backoffice.impersonation.end", payload: { reason: reason.to_s }, actor: operator_record)
        self
      end

      def operator_record
        operator_type.safe_constantize&.find_by(id: operator_id)
      end

      private

      def reason_long_enough
        minimum = Lucid::Backoffice.configuration.reveal_reason_min
        errors.add(:reason, "must have at least #{minimum} characters") if reason.to_s.strip.length < minimum
      end
    end
  end
end
