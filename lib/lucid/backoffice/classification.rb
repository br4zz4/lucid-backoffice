require "yaml"

module Lucid
  module Backoffice
    # Which privacy category a column belongs to. A column nobody classified is +unclassified+,
    # and every category except +public+ is masked until revealed.
    module Classification
      PUBLIC = "public".freeze
      UNCLASSIFIED = "unclassified".freeze
      PUBLIC_BY_CONVENTION = /\A(id|created_at|updated_at)\z|_id\z|_type\z/

      module_function

      # @return [String] the category of +table+.+column+
      def category_for(table, column)
        return PUBLIC if column.to_s.match?(PUBLIC_BY_CONVENTION)

        entries.dig(table.to_s, column.to_s) || UNCLASSIFIED
      end

      # @return [Hash{String => Hash{String => String}}] the YAML, validated against the configured categories
      # @raise [Error::ConfigurationConflict] an entry names a category that is not configured
      def load!(path = Lucid::Backoffice.configuration.classification_path)
        @entries = path ? parse(path) : {}
      end

      def reset!
        @entries = nil
      end

      def entries
        @entries || load!
      end

      def parse(path)
        categories = Lucid::Backoffice.configuration.categories
        data = YAML.safe_load_file(path.to_s) || {}
        data.each_with_object({}) do |(table, columns), result|
          result[table.to_s] = (columns || {}).to_h do |column, category|
            unless categories.include?(category.to_s)
              raise Error::ConfigurationConflict, "#{path}: #{table}.#{column} has unknown category #{category.inspect}"
            end

            [column.to_s, category.to_s]
          end
        end
      end
      private_class_method :parse
    end
  end
end
