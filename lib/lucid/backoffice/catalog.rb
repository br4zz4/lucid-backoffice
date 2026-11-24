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

      MAX_RELATED = 20

      # @return [Hash{String => String}] column of +table+ => table it points to: the database foreign keys,
      #   then associations other Resources declare toward +table+, then the +x_id+ => +xs+ convention
      def references(schema, table)
        known = tables(schema)
        found = foreign_keys(schema).select { |row| row[:table] == table.to_s }.to_h { |row| [row[:column], row[:target]] }
        Resource.registry.each do |resource|
          resource.associations.each { |association| found[association.foreign_key] ||= resource.table if association.table == table.to_s }
        end
        columns(schema, table).each do |column|
          next unless column.name.end_with?("_id") && !found.key?(column.name)

          guess = column.name.delete_suffix("_id").pluralize
          found[column.name] = guess if known.include?(guess)
        end
        found.select { |_column, target| known.include?(target) }
      end

      # @return [Array<Hash>] tables whose +column+ points at +table+: foreign keys, then the associations
      #   the Resource of +table+ declares; at most {MAX_RELATED}
      def referenced_by(schema, table)
        known = tables(schema)
        rows = foreign_keys(schema).select { |row| row[:target] == table.to_s }.map { |row| { table: row[:table], column: row[:column] } }
        Resource.for(table)&.associations&.each { |association| rows << { table: association.table, column: association.foreign_key } }
        rows.uniq.select { |row| known.include?(row[:table]) && columns(schema, row[:table]).any? { |column| column.name == row[:column] } }
            .first(MAX_RELATED)
      end

      def foreign_keys(schema)
        connection.select_rows(
          "SELECT tc.table_name, kcu.column_name, ccu.table_name FROM information_schema.table_constraints tc " \
          "JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema " \
          "JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema " \
          "WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = #{connection.quote(schema)}"
        ).map { |table, column, target| { table: table, column: column, target: target } }
      end

      def connection
        ActiveRecord::Base.lease_connection
      end
    end
  end
end
