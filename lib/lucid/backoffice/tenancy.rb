require "lucid/backoffice/tenancy/null"

module Lucid
  module Backoffice
    # What the back office needs to know about tenants. An adapter answers: +tenants+, +find(identifier)+,
    # +identifier(tenant)+, +label(tenant)+, +schema_for(tenant)+ (nil means the shared schema),
    # +shared_schema+, +health(tenant)+ (nil hides the schema health section).
    module Tenancy
      module_function

      def adapter
        setting = Lucid::Backoffice.configuration.tenancy
        case setting
        when :none, nil then @null ||= Null.new
        when :lucid_tenancy
          unless defined?(Adapters::LucidTenancy)
            raise Error::ConfigurationConflict, "config.tenancy = :lucid_tenancy needs require \"lucid/backoffice/adapters/lucid_tenancy\""
          end

          @lucid_tenancy ||= Adapters::LucidTenancy.new
        else setting
        end
      end

      def reset!
        @null = @lucid_tenancy = nil
      end
    end
  end
end
