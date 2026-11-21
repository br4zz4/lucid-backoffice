module Lucid
  module Backoffice
    # The panel records its own use. If the record cannot be written the data is not shown: the error
    # propagates before any query reads a row.
    module PanelActivity
      module_function

      def browse(table:, tenant: nil)
        record("backoffice.browse", table, nil, tenant)
      end

      def view(table:, id:, tenant: nil)
        record("backoffice.view", table, id, tenant)
      end

      def record(name, table, id, tenant)
        Current.tenant_identifier ||= Reveal.tenant_identifier(tenant)
        Activity.record(name: name, subjects: [{ "type" => "Table", "name" => table.to_s, "id" => id }.compact])
      end
      private_class_method :record
    end
  end
end
