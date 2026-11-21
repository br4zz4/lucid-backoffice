module Lucid
  module Backoffice
    # What the app and plugins add to the panel: menu items, dashboard cards, tenant sections, permissions.
    module Registry
      MenuItem = Data.define(:label, :path, :permission, :group)
      Card = Data.define(:key, :label, :value, :permission, :format)
      Section = Data.define(:name, :partial, :permission)
      Period = Data.define(:key, :range) do
        def self.for(key)
          days = key.to_s == "month" ? 30 : 7
          new(key: days == 30 ? "month" : "week", range: (Time.current - days.days)..Time.current)
        end
      end

      # Collects the declarations of one +register+ block.
      class Collector
        attr_reader :menu_items, :cards, :sections, :permissions

        def initialize
          @menu_items = []
          @cards = []
          @sections = []
          @permissions = []
        end

        def menu(label:, path:, permission: :view_dashboard, group: nil)
          @menu_items << MenuItem.new(label: label, path: path, permission: permission, group: group)
        end

        def card(key, label:, value:, permission: :view_dashboard, format: :number)
          @cards << Card.new(key: key.to_sym, label: label, value: value, permission: permission, format: format)
        end

        def tenant_section(name, partial:, permission: :view_tenant)
          @sections << Section.new(name: name.to_sym, partial: partial, permission: permission)
        end

        def permission(name)
          @permissions << name.to_sym
        end
      end

      module_function

      def register(name, &block)
        collector = Collector.new
        block.call(collector)
        entries[name.to_sym] = collector
      end

      def entries
        @entries ||= {}
      end

      def menu_items = entries.values.flat_map(&:menu_items)
      def cards = entries.values.flat_map(&:cards)
      def sections = entries.values.flat_map(&:sections)
      def permissions = entries.values.flat_map(&:permissions)

      def reset!
        @entries = {}
      end
    end
  end
end
