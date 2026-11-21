module Lucid
  module Backoffice
    # The tables and columns of one schema, read from the catalog. Internal tables, the gem's own,
    # configured hidden tables and secret columns never appear.
    module Catalog
      INTERNAL = %w[schema_migrations ar_internal_metadata].freeze
      Column = Data.define(:name, :type, :category)

      TYPES = {
        "character varying" => :string, "character" => :string, "citext" => :string, "uuid" => :string, "text" => :text,
        "integer" => :integer, "smallint" => :integer, "bigint" => :integer,
        "numeric" => :decimal, "double precision" => :float, "real" => :float,
        "boolean" => :boolean, "date" => :date, "json" => :json, "jsonb" => :json,
        "timestamp without time zone" => :datetime, "timestamp with time zone" => :datetime
      }.freeze

      module_function

      def tables(schema)
        config = Lucid::Backoffice.configuration
        hidden = INTERNAL + config.hidden_tables.map(&:to_s)
        connection.select_values(
          "SELECT table_name FROM information_schema.tables WHERE table_schema = #{connection.quote(schema)} " \
          "AND table_type = 'BASE TABLE' ORDER BY table_name"
        ).reject { |name| hidden.include?(name) || name.start_with?("lucid_backoffice_") }
      end

      def table?(schema, table)
        tables(schema).include?(table.to_s)
      end

      # @return [Array<Column>] visible columns of +table+ with their type and privacy category
      def columns(schema, table)
        secret = Lucid::Backoffice.configuration.secret_columns
        connection.select_rows(
          "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = #{connection.quote(schema)} " \
          "AND table_name = #{connection.quote(table.to_s)} ORDER BY ordinal_position"
        ).reject { |name, _| name.match?(secret) }.map do |name, type|
          Column.new(name: name, type: TYPES.fetch(type, :string), category: Classification.category_for(table, name))
        end
      end

      def connection
        ActiveRecord::Base.lease_connection
      end
    end
  end
end
