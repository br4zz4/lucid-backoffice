module Lucid
  module Backoffice
    # Hides a value by its type. Public and revealed values pass through.
    module Mask
      LONG_TEXT = 40
      EMPTY = "—".freeze
      TEXT = "•••••".freeze
      TIME = "••/••/••••".freeze
      NUMBER = "•••".freeze
      TIME_TYPES = %i[date datetime time timestamp timestamptz].freeze
      NUMBER_TYPES = %i[integer bigint float decimal boolean].freeze

      module_function

      # @param value [Object] the raw value
      # @param category [String] its privacy category
      # @param column_type [Symbol] the column type (:string, :text, :date, :integer, ...)
      # @param revealed [Boolean] whether the operator revealed this category
      def call(value:, category:, column_type:, revealed: false)
        return value if category.to_s == Classification::PUBLIC || revealed
        return EMPTY if value.nil?

        type = column_type.to_sym
        return TIME if TIME_TYPES.include?(type)
        return NUMBER if NUMBER_TYPES.include?(type)

        text = value.to_s
        text.length > LONG_TEXT ? "[texto, #{text.length} caracteres]" : TEXT
      end
    end
  end
end
