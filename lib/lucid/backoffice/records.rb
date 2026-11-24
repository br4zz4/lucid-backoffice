module Lucid
  module Backoffice
    # Read-only access to the rows of a catalog table. Identifiers always come from the catalog, never
    # from a parameter, and values leave already masked.
    module Records
      Page = Data.define(:columns, :rows, :page, :pages, :total, :ignored_filters)
      Cell = Data.define(:column, :value, :masked, :link) do
        def initialize(column:, value:, masked:, link: nil) = super
      end
      Related = Data.define(:table, :column, :count)

      class NotFound < Error; end

      module_function

      # @param filters [Hash] equality filters, applied only to usable columns; the rest is ignored
      # @param query [Query, nil] filters, search and sort together; +filters+ are merged into it
      # @param revealed [#include?] categories the operator revealed
      # @raise [NotFound] +table+ is not in the catalog of +schema+
      def list(schema:, table:, filters: {}, query: nil, page: 1, revealed: [], resource: nil)
        columns = visible(schema, table, resource)
        query = Query.new(filters: filters.to_h.merge(query&.filters.to_h), search: query&.search, sort: query&.sort, dir: query&.dir)
        ignored = query.ignored(columns, revealed)
        ignored << "search" if query.search && query.searchable_columns(columns, revealed, declared: resource&.searchable.presence).empty?
        references = Catalog.references(schema, table)
        conditions = conditions_for(query, columns, revealed, resource)
        per = Lucid::Backoffice.configuration.page_size
        total = connection.select_value("SELECT COUNT(*) FROM #{qualified(schema, table)}#{where(conditions)}").to_i
        page = [page.to_i, 1].max
        rows = connection.select_all(
          "SELECT #{select_list(columns)} FROM #{qualified(schema, table)}#{where(conditions)}#{order(columns, query, revealed)} " \
          "LIMIT #{per} OFFSET #{(page - 1) * per}"
        ).to_a
        Page.new(columns: columns, rows: rows.map { |row| cells(row, columns, revealed, references) }, page: page,
                 pages: [(total / per.to_f).ceil, 1].max, total: total, ignored_filters: ignored)
      end

      # @raise [NotFound] the table or the record does not exist
      def find(schema:, table:, id:, revealed: [], resource: nil)
        columns = visible(schema, table, resource)
        raise NotFound, "no such record" unless columns.any? { |column| column.name == "id" } && Integer(id, exception: false)

        row = connection.select_all("SELECT #{select_list(columns)} FROM #{qualified(schema, table)} WHERE id = #{Integer(id)} LIMIT 1").first
        raise NotFound, "no such record" unless row

        cells(row, columns, revealed, Catalog.references(schema, table))
      end

      # @return [Array<Related>] tables that point at the record, with how many rows do
      def related(schema:, table:, id:)
        id = Integer(id, exception: false)
        return [] unless id

        Catalog.referenced_by(schema, table).filter_map do |reference|
          count = connection.select_value(
            "SELECT COUNT(*) FROM #{qualified(schema, reference[:table])} WHERE #{connection.quote_column_name(reference[:column])} = #{id}"
          ).to_i
          Related.new(table: reference[:table], column: reference[:column], count: count) if count.positive?
        end
      end

      def visible(schema, table, resource)
        raise NotFound, "no such table" unless Catalog.table?(schema, table)

        columns = Catalog.columns(schema, table)
        resource ? resource.visible_columns(columns) : columns
      end

      def conditions_for(query, columns, revealed, resource)
        conditions = query.filters.filter_map do |name, value|
          column = columns.find { |candidate| candidate.name == name }
          next unless column && query.applicable_filter?(name, columns, revealed)

          equality(column, value)
        end
        conditions << search_condition(query, columns, revealed, resource)
        conditions.compact
      end

      def equality(column, value)
        quoted = connection.quote_column_name(column.name)
        return "#{quoted} = #{Integer(value.to_s)}" if column.type == :integer

        "CAST(#{quoted} AS text) = #{connection.quote(value.to_s)}"
      end

      def search_condition(query, columns, revealed, resource)
        return nil unless query.search

        searchable = query.searchable_columns(columns, revealed, declared: resource&.searchable.presence)
        return "FALSE" if searchable.empty?

        pattern = connection.quote("%#{ActiveRecord::Base.sanitize_sql_like(query.search)}%")
        "(" + searchable.map { |column| "CAST(#{connection.quote_column_name(column.name)} AS text) ILIKE #{pattern}" }.join(" OR ") + ")"
      end

      def cells(row, columns, revealed, references = {})
        columns.map do |column|
          open = revealed.include?(column.category)
          value = Mask.call(value: row[column.name], category: column.category, column_type: column.type, revealed: open)
          masked = !open && column.category != Classification::PUBLIC
          target = references[column.name]
          link = { table: target, id: row[column.name] } if target && !masked && !row[column.name].nil?
          Cell.new(column: column, value: value, masked: masked, link: link)
        end
      end

      def qualified(schema, table)
        "#{connection.quote_table_name(schema)}.#{connection.quote_table_name(table)}"
      end

      def select_list(columns)
        columns.map { |column| connection.quote_column_name(column.name) }.join(", ")
      end

      def where(conditions)
        conditions.empty? ? "" : " WHERE #{conditions.join(' AND ')}"
      end

      def order(columns, query, revealed)
        terms = []
        terms << "#{connection.quote_column_name(query.sort)} #{query.dir.upcase}" if query.sortable?(columns, revealed)
        terms << "#{connection.quote_column_name('id')} ASC" if columns.any? { |column| column.name == "id" } && query.sort != "id"
        terms.empty? ? "" : " ORDER BY #{terms.join(', ')}"
      end

      def connection
        ActiveRecord::Base.lease_connection
      end
    end
  end
end
