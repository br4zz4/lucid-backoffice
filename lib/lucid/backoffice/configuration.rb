module Lucid
  module Backoffice
    # Options of the back office, set with {Lucid::Backoffice.configure}.
    class Configuration
      DEFAULT_CATEGORIES = %w[public contact documents minors financial free_text unclassified].freeze
      DEFAULT_SECRET_COLUMNS = /password|token|secret|digest|otp|encrypted/i

      # Integration with the host app.
      attr_accessor :current_operator, :authenticate, :sign_out_path, :operator_label, :current_actor
      attr_reader :authorize

      # Data.
      attr_accessor :tenancy, :classification_path, :hidden_tables, :secret_columns, :page_size, :resources_path
      attr_reader :categories

      # Reveals.
      attr_accessor :reveal_duration, :reveal_reason_min

      # Activity trail.
      attr_accessor :activity_retention, :activity_purge_batch

      # Appearance.
      attr_accessor :title, :brand_color, :layout, :terms

      def initialize
        @authorize = ->(_operator, _permission, _context) { false }
        @tenancy = :none
        @categories = DEFAULT_CATEGORIES.dup
        @hidden_tables = []
        @secret_columns = DEFAULT_SECRET_COLUMNS
        @page_size = 25
        @reveal_duration = 15 * 60
        @reveal_reason_min = 10
        @activity_retention = 6 * 30 * 24 * 3600
        @activity_purge_batch = 1000
        @title = "Back office"
        @terms = {}
      end

      # @param callable [#call] +->(operator, permission, context) { }+; the default denies everything
      def authorize=(callable)
        raise Error::ConfigurationConflict, "authorize must respond to call" unless callable.respond_to?(:call)

        @authorize = callable
      end

      def categories=(list)
        @categories = Array(list).map(&:to_s)
      end

      # @raise [Error::ConfigurationConflict] naming the key that is missing or inconsistent
      def validate!
        %i[current_operator authenticate].each do |key|
          raise Error::ConfigurationConflict, "config.#{key} is required" unless public_send(key).respond_to?(:call)
        end
        if classification_path && !File.file?(classification_path.to_s)
          raise Error::ConfigurationConflict, "config.classification_path #{classification_path.inspect} does not exist"
        end
        raise Error::ConfigurationConflict, "config.categories must include public and unclassified" unless (%w[public unclassified] - categories).empty?

        self
      end
    end
  end
end
