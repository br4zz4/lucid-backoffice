module Lucid
  module Backoffice
    # Optional fine tuning of one table. Without a declaration a table already works, fully masked;
    # a Resource only adjusts what is shown.
    #
    #   class Purchases < Lucid::Backoffice::Resource
    #     table :purchases
    #     group :billing
    #     columns :id, :email, :status
    #     column :status, :badge
    #     search :id
    #     label(from: :email) { |row| row["email"] }
    #   end
    class Resource
      Association = Data.define(:name, :table, :foreign_key)

      class << self
        def inherited(subclass)
          super
          Resource.registry << subclass
        end

        def registry
          @registry ||= []
        end

        def for(table)
          registry.find { |resource| resource.table == table.to_s }
        end

        def reset!
          registry.clear
        end

        def table(name = nil)
          name ? @table = name.to_s : @table
        end

        def group(name = nil)
          name ? @group = name.to_sym : @group
        end

        def columns(*names)
          names.any? ? @columns = names.map(&:to_s) : @columns
        end

        def detail(*names)
          names.any? ? @detail = names.map(&:to_s) : @detail
        end

        def hide(*names)
          @hidden = (hidden + names.map(&:to_s)).uniq
        end

        def hidden
          @hidden ||= []
        end

        def column(name, type = nil, render: nil, from: nil)
          display[name.to_s] = { type: type, render: render, from: from&.to_s }
        end

        def display
          @display ||= {}
        end

        # Columns the operator may search by id: only public columns, because searching a masked column
        # would leak its value by trial and error.
        def search(*names)
          names.each do |name|
            category = Classification.category_for(table, name)
            unless category == Classification::PUBLIC
              raise Error::ConfigurationConflict, "#{self.name}: search #{name.inspect} is #{category}; only public columns can be searched"
            end
          end
          @search = names.map(&:to_s)
        end

        def searchable
          @search || []
        end

        def filter(name)
          (@filters ||= []) << name.to_sym
        end

        def filters
          @filters || []
        end

        def association(name, table:, foreign_key:)
          (@associations ||= []) << Association.new(name: name.to_sym, table: table.to_s, foreign_key: foreign_key.to_s)
        end

        def associations
          @associations || []
        end

        def label(from: nil, &block)
          return @label unless block

          @label = { block: block, from: from&.to_s }
        end

        # @return [String] the label of a row, masked by the category of the column it came from
        def label_for(row, revealed: [])
          return row["id"].to_s unless @label

          category = @label[:from] ? Classification.category_for(table, @label[:from]) : Classification::UNCLASSIFIED
          value = @label[:block].call(row)
          Mask.call(value: value, category: category, column_type: :string, revealed: revealed.include?(category))
        end

        # @return [Array<Catalog::Column>] +columns+ without hidden ones, in the declared order
        def visible_columns(columns, order: @columns)
          shown = columns.reject { |column| hidden.include?(column.name) }
          return shown unless order

          order.filter_map { |name| shown.find { |column| column.name == name } }
        end
      end
    end
  end
end
