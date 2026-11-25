require "digest"

module Lucid
  module Backoffice
    class Action
      # What an action is about to change, before and after. Values stay raw inside and leave masked.
      class Preview
        Change = Data.define(:label, :before, :after, :category, :revealed) do
          def initialize(label:, before:, after:, category:, revealed: false) = super
        end
        Listing = Data.define(:title, :items)

        attr_reader :changes, :listings

        def initialize
          @changes = []
          @listings = []
        end

        # @param record [ActiveRecord::Base] the record whose +attribute+ changes
        # @param to [Object] the new value
        def change(record, attribute, to:)
          category = Classification.category_for(record.class.table_name, attribute)
          @changes << Change.new(label: "#{record.class.name} ##{record.id} #{attribute}", before: record.public_send(attribute), after: to, category: category)
        end

        def list(title, items)
          @listings << Listing.new(title: title, items: Array(items))
        end

        # @return [String] digest of what was read; if it differs at execution the state changed
        def snapshot
          Digest::SHA256.hexdigest(JSON.generate([changes.map { |c| [c.label, c.before.to_s] }, listings.map { |l| [l.title, l.items.map(&:to_s)] }]))
        end

        # @return [Array<Change>] the changes with values masked unless the operator revealed the category
        def masked(revealed: [])
          changes.map do |c|
            open = revealed.include?(c.category)
            Change.new(label: c.label, category: c.category, revealed: open && c.category != Classification::PUBLIC,
                       before: Mask.call(value: c.before, category: c.category, column_type: type_of(c.before), revealed: open),
                       after: Mask.call(value: c.after, category: c.category, column_type: type_of(c.after), revealed: open))
          end
        end

        private

        def type_of(value)
          case value
          when Integer, Float, BigDecimal, true, false then :integer
          when Date, Time, DateTime, ActiveSupport::TimeWithZone then :datetime
          else :string
          end
        end
      end
    end
  end
end
