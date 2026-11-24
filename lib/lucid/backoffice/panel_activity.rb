module Lucid
  module Backoffice
    # The panel records its own use. If the record cannot be written the data is not shown: the error
    # propagates before any query reads a row.
    module PanelActivity
      module_function

      # @param criteria [Array<String>] the names of the columns used to filter, search or sort, never the values
      def browse(table:, tenant: nil, criteria: [])
        names = criteria.map(&:to_s).grep(Activity::Event::TOKEN).uniq.sort
        record("backoffice.browse", table, nil, tenant, names.any? ? { criteria: names } : nil)
      end

      def view(table:, id:, tenant: nil)
        record("backoffice.view", table, id, tenant)
      end

      def record(name, table, id, tenant, payload = nil)
        Current.tenant_identifier ||= Reveal.tenant_identifier(tenant)
        Activity.record(name: name, subjects: [{ "type" => "Table", "name" => table.to_s, "id" => id }.compact], **{ payload: payload }.compact)
      end
      private_class_method :record
    end
  end
end
