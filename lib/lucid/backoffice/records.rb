module Lucid
  module Backoffice
    # Read-only access to the rows of a catalog table. Identifiers always come from the catalog, never
    # from a parameter, and values leave already masked.
    module Records
      Page = Data.define(:columns, :rows, :page, :pages, :total, :ignored_filters)
      Cell = Data.define(:column, :value, :masked)

      class NotFound < Error; end

      module_function

      # @param filters [Hash] only +id+ and +*_id+ with an integer value are applied; the rest is ignored
      # @param revealed [#include?] categories the operator revealed
      # @raise [NotFound] +table+ is not in the catalog of +schema+
      def list(schema:, table:, filters: {}, page: 1, revealed: [], resource: nil)
        columns = visible(schema, table, resource)
        applied, ignored = split_filters(filters, columns)
        per = Lucid::Backoffice.configuration.page_size
        total = connection.select_value("SELECT COUNT(*) FROM #{qualified(schema, table)}#{where(applied)}").to_i
        page = [page.to_i, 1].max
        rows = connection.select_all(
          "SELECT #{select_list(columns)} FROM #{qualified(schema, table)}#{where(applied)}#{order(columns)} LIMIT #{per} OFFSET #{(page - 1) * per}"
        ).to_a
        Page.new(columns: columns, rows: rows.map { |row| cells(row, columns, revealed) }, page: page,
                 pages: [(total / per.to_f).ceil, 1].max, total: total, ignored_filters: ignored)
      end

      # @raise [NotFound] the table or the record does not exist
      def find(schema:, table:, id:, revealed: [], resource: nil)
        columns = visible(schema, table, resource)
        raise NotFound, "no such record" unless columns.any? { |column| column.name == "id" } && Integer(id, exception: false)

        row = connection.select_all("SELECT #{select_list(columns)} FROM #{qualified(schema, table)} WHERE id = #{Integer(id)} LIMIT 1").first
        raise NotFound, "no such record" unless row

        cells(row, columns, revealed)
      end

      def visible(schema, table, resource)
        raise NotFound, "no such table" unless Catalog.table?(schema, table)

        columns = Catalog.columns(schema, table)
        resource ? resource.visible_columns(columns) : columns
      end

      def split_filters(filters, columns)
        allowed = columns.select { |column| column.name == "id" || column.name.end_with?("_id") }.map(&:name)
        applied = {}
        ignored = []
        filters.to_h.each do |name, value|
          integer = Integer(value.to_s, exception: false)
          if allowed.include?(name.to_s) && integer
            applied[name.to_s] = integer
          else
            ignored << name.to_s
          end
        end
        [applied, ignored]
      end

      def cells(row, columns, revealed)
        columns.map do |column|
          open = revealed.include?(column.category)
          value = Mask.call(value: row[column.name], category: column.category, column_type: column.type, revealed: open)
          Cell.new(column: column, value: value, masked: !open && column.category != Classification::PUBLIC)
        end
      end

      def qualified(schema, table)
        "#{connection.quote_table_name(schema)}.#{connection.quote_table_name(table)}"
      end

      def select_list(columns)
        columns.map { |column| connection.quote_column_name(column.name) }.join(", ")
      end

      def where(applied)
        return "" if applied.empty?

        " WHERE " + applied.map { |name, value| "#{connection.quote_column_name(name)} = #{value}" }.join(" AND ")
      end

      def order(columns)
        columns.any? { |column| column.name == "id" } ? " ORDER BY #{connection.quote_column_name('id')}" : ""
      end

      def connection
        ActiveRecord::Base.lease_connection
      end
    end
  end
end
