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

        # Columns the text search covers. A hidden column can never be searched; a masked one is searched
        # only while the operator has revealed its category.
        def search(*names)
          names.each do |name|
            next unless hidden.include?(name.to_s) || name.to_s.match?(Lucid::Backoffice.configuration.secret_columns) ||
                        Classification.category_for(table, name) == "secret"

            raise Error::ConfigurationConflict, "#{self.name}: search #{name.inspect} is a hidden column and cannot be searched"
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

        # Adds an "Edit" action over these columns and nothing else. +with:+ routes the write through a
        # Command, so its guards, validations and events apply.
        def editable(*names, with: nil)
          resource_table = table
          fields = names.map(&:to_sym)
          types = editable_types(resource_table, fields)
          klass = action_class("edit_#{resource_table}", "Edit")
          klass.on(resource_table)
          klass.label("Edit")
          klass.permission(:update_record)
          fields.each { |field| klass.field(field, types.fetch(field, :string), required: false) }
          if with
            klass.perform(with: with)
          else
            klass.perform { record.update!(self.class.fields.keys.to_h { |field| [field, public_send(field)] }) }
          end
          @editable = klass
        end

        def editable_action
          @editable
        end

        # Adds a "New record" action over these columns, on the table as a whole. By default it runs
        # +Model.create!+; +with:+ routes it through a Command. Hidden columns cannot be fields.
        def creatable(*names, with: nil)
          resource_table = table
          fields = names.map(&:to_sym)
          model = record_model!(:creatable)
          reject_hidden!(:creatable, fields)
          types = editable_types(resource_table, fields)
          klass = action_class("create_#{resource_table}", "Create")
          klass.on(resource_table, collection: true)
          klass.label("Novo registro")
          klass.permission(:create_record)
          klass.landing(:record)
          fields.each { |field| klass.field(field, types.fetch(field, :string), required: false) }
          klass.preview { |p| p.list("Novo registro", self.class.fields.keys.map { |field| "#{field}: #{public_send(field)}" }) }
          if with
            klass.perform(with: with)
          else
            klass.perform do
              values = self.class.fields.keys.to_h { |field| [field, public_send(field)] }
              model.create!(values)
            rescue ActiveRecord::RecordInvalid => e
              Action::Failure.new(type: :invalid, errors: [e.record.errors.full_messages.to_sentence])
            end
          end
          @creatable = klass
        end

        def creatable_action
          @creatable
        end

        # Adds a "Delete record" action (danger high, typing the record id). +with:+ routes it through a Command.
        def destroyable(with: nil)
          resource_table = table
          record_model!(:destroyable)
          klass = action_class("destroy_#{resource_table}", "Destroy")
          klass.on(resource_table)
          klass.label("Excluir registro")
          klass.danger(:high)
          klass.permission(:destroy_record)
          klass.landing(:list)
          if with
            klass.perform(with: with)
          else
            klass.perform do
              record.destroy ? record : Action::Failure.new(type: :not_destroyed, errors: [record.errors.full_messages.to_sentence])
            end
          end
          @destroyable = klass
        end

        def destroyable_action
          @destroyable
        end

        def action_class(key, prefix)
          resource_table = table
          klass = Class.new(Action)
          klass.define_singleton_method(:key) { key }
          klass.define_singleton_method(:name) { "Lucid::Backoffice::#{prefix}#{resource_table.to_s.camelize}" }
          klass
        end

        def record_model!(kind)
          model = table.to_s.classify.safe_constantize
          return model if model && model < ActiveRecord::Base

          raise Error::ConfigurationConflict, "#{name || self}: #{kind} needs an ActiveRecord model for table #{table.inspect}"
        end

        def reject_hidden!(kind, fields)
          fields.each do |field|
            next unless hidden.include?(field.to_s) || field.to_s.match?(Lucid::Backoffice.configuration.secret_columns)

            raise Error::ConfigurationConflict, "#{name || self}: #{kind} #{field.inspect} is a hidden column"
          end
        end

        def editable_types(table, fields)
          columns = Catalog.columns(Tenancy.adapter.shared_schema, table).to_h { |column| [column.name.to_sym, column.type] }
          fields.to_h { |field| [field, { integer: :integer, boolean: :boolean, date: :date, text: :text }.fetch(columns[field], :string)] }
        rescue ActiveRecord::ActiveRecordError
          {}
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
