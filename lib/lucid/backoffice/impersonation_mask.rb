module Lucid
  module Backoffice
    # Include in ApplicationRecord. While an impersonation is active, records of the app come out masked
    # (text hidden, dates reduced to the year) unless the operator revealed that category, and read-only.
    # The tables of the back office itself are never touched.
    module ImpersonationMask
      extend ActiveSupport::Concern

      TEXT = "•••••".freeze

      included do
        class_attribute :lucid_backoffice_unmasked, instance_writer: false, default: false
        after_initialize :lucid_backoffice_mask_for_impersonation
      end

      private

      def lucid_backoffice_mask_for_impersonation
        return unless Lucid::Backoffice.impersonating?
        return if self.class.lucid_backoffice_unmasked || self.class.table_name.to_s.start_with?("lucid_backoffice_")

        revealed = Current.revealed_categories ||= Reveal.categories_for(operator: Current.actor, tenant: Current.tenant_identifier)
        self.class.columns.each do |column|
          category = Classification.category_for(self.class.table_name, column.name)
          next if category == Classification::PUBLIC || revealed.include?(category) || !has_attribute?(column.name)

          masked = lucid_backoffice_masked_value(self[column.name], column.type)
          self[column.name] = masked unless masked.equal?(:keep)
        end
        clear_changes_information
        readonly!
      end

      def lucid_backoffice_masked_value(value, type)
        return :keep if value.nil?

        case type
        when :string, :text then TEXT
        when :date then value.beginning_of_year
        when :datetime, :timestamp, :timestamptz then value.beginning_of_year
        else :keep
        end
      end
    end
  end
end
