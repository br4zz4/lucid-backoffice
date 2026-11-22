require "lucid/backoffice"

module Lucid
  module Backoffice
    # Helpers for the tests of an app that uses the back office: +require "lucid/backoffice/test_helpers"+
    # and include {TestHelpers}.
    module TestHelpers
      # Configures +operator+ as the signed-in operator, allowed exactly +permissions+.
      def with_operator(operator, permissions: [])
        config = Lucid::Backoffice.configuration
        config.current_operator = ->(_controller) { operator }
        config.authenticate = ->(_controller) { true }
        config.authorize = ->(_operator, permission, _context) { permissions.include?(permission) }
        operator
      end

      # Reveals +category+ for +operator+ (in +tenant+), bypassing authorization, as an already granted reveal.
      def grant_reveal(operator:, category:, tenant: nil, reason: "test reveal reason")
        Reveal.create!(operator_type: operator.class.name, operator_id: operator.id,
                       tenant_identifier: Reveal.tenant_identifier(tenant), category: category.to_s, reason: reason,
                       expires_at: Time.current + Lucid::Backoffice.configuration.reveal_duration)
      end

      # Asserts +value+ is what the back office shows instead of real data.
      def assert_masked(value, message = nil)
        masks = [Mask::EMPTY, Mask::TEXT, Mask::TIME, Mask::NUMBER]
        assert masks.include?(value) || value.to_s.match?(/\A\[texto, \d+ caracteres\]\z/), message || "expected #{value.inspect} to be masked"
      end
    end
  end
end
