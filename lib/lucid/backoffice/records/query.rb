module Lucid
  module Backoffice
    module Records
      # What the operator asked of a list: equality filters, a text search and a sort. A column is only
      # usable (to filter, search or sort) when the operator can read it right now: it is not hidden
      # (the catalog and the Resource already drop those) and its category is public or revealed.
      class Query
        DIRECTIONS = %w[asc desc].freeze
        TEXT_TYPES = %i[string text].freeze

        attr_reader :filters, :search, :sort, :dir

        def initialize(filters: {}, search: nil, sort: nil, dir: nil)
          @filters = filters.to_h.transform_keys(&:to_s)
          @search = search.to_s.strip.presence
          @sort = sort.to_s.presence
          @dir = DIRECTIONS.include?(dir.to_s.downcase) ? dir.to_s.downcase : "asc"
        end

        def self.usable?(column, revealed)
          column.category == Classification::PUBLIC || Array(revealed).include?(column.category)
        end

        def usable?(column, revealed)
          self.class.usable?(column, revealed)
        end

        # @return [Array<String>] names of the criteria that cannot be applied: not a usable column, or a
        #   value that does not fit the column
        def ignored(columns, revealed)
          ignored = filters.keys.reject { |name| applicable_filter?(name, columns, revealed) }
          ignored << sort if sort && !sortable?(columns, revealed)
          ignored
        end

        def sortable?(columns, revealed)
          column = columns.find { |candidate| candidate.name == sort }
          !column.nil? && usable?(column, revealed)
        end

        def searchable_columns(columns, revealed, declared: nil)
          pool = declared ? columns.select { |column| declared.include?(column.name) } : columns.select { |column| TEXT_TYPES.include?(column.type) }
          pool.select { |column| usable?(column, revealed) }
        end

        def applicable_filter?(name, columns, revealed)
          column = columns.find { |candidate| candidate.name == name.to_s }
          return false unless column && usable?(column, revealed)

          column.type != :integer || !Integer(filters[name].to_s, exception: false).nil?
        end
      end
    end
  end
end
