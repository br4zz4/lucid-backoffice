module Lucid
  module Backoffice
    # An operator unmasking one category of data, in one tenant, with a reason and a deadline.
    class Reveal < ActiveRecord::Base
      self.table_name = "lucid_backoffice_reveals"

      validates :operator_type, :operator_id, :category, :expires_at, presence: true
      validate :reason_long_enough, on: :create
      validate :category_known, on: :create

      scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

      class << self
        # @raise [Error::Forbidden] the operator may not reveal
        # @raise [ActiveRecord::RecordInvalid] the reason is too short or the category is unknown
        def grant(operator:, category:, reason:, tenant: nil)
          Authorization.authorize!(operator, :reveal, { tenant: tenant, category: category.to_s })
          identifier = tenant_identifier(tenant)
          transaction do
            reveal = create!(operator_type: operator.class.name, operator_id: operator.id, tenant_identifier: identifier,
                             category: category.to_s, reason: reason.to_s.strip,
                             expires_at: Time.current + Lucid::Backoffice.configuration.reveal_duration)
            Activity.record(name: "backoffice.reveal.grant", payload: { category: reveal.category }, reason: reveal.reason, actor: operator)
            reveal
          end
        end

        # Ends a reveal now, so the next request masks again.
        def revoke(reveal, operator:)
          Authorization.authorize!(operator, :reveal, { tenant: reveal.tenant_identifier, category: reveal.category })
          transaction do
            reveal.update!(revoked_at: Time.current) unless reveal.revoked_at
            Activity.record(name: "backoffice.reveal.revoke", payload: { category: reveal.category }, actor: operator)
          end
          reveal
        end

        # @return [Array<String>] categories this operator has revealed, still valid, in this tenant
        def categories_for(operator:, tenant: nil)
          return [] unless operator

          active.where(operator_type: operator.class.name, operator_id: operator.id, tenant_identifier: tenant_identifier(tenant))
                .pluck(:category).uniq
        end

        def tenant_identifier(tenant)
          return nil if tenant.nil?

          tenant.is_a?(String) || tenant.is_a?(Symbol) ? tenant.to_s : Tenancy.adapter.identifier(tenant)
        end
      end

      def active?
        revoked_at.nil? && expires_at > Time.current
      end

      private

      def reason_long_enough
        minimum = Lucid::Backoffice.configuration.reveal_reason_min
        errors.add(:reason, "must have at least #{minimum} characters") if reason.to_s.strip.length < minimum
      end

      def category_known
        errors.add(:category, "is not a configured category") unless Lucid::Backoffice.configuration.categories.include?(category.to_s)
      end
    end
  end
end
