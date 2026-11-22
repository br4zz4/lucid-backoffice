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

      # Impersonation hooks and limits. The app supplies how to find and sign in a user.
      Impersonation = Struct.new(:find_user, :sign_in, :sign_out, :entry_url, :return_url, :duration, :tenant_for_request, :read_only_except)

      # Appearance.
      attr_accessor :title, :layout, :terms
      attr_reader :brand_color, :theme, :stylesheet, :extra_stylesheets

      STYLESHEET_REFERENCE = %r{\A(/(?!/)|https?://)[^\s"'<>\\]*\z}

      def impersonation
        @impersonation ||= Impersonation.new(nil, nil, nil, nil, nil, 30 * 60, nil, [])
      end

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
        @theme = {}
        @stylesheet = :default
        @extra_stylesheets = []
      end

      # The accent color of the panel, +#rgb+ or +#rrggbb+; the text over it is chosen for contrast.
      def brand_color=(color)
        Theme.validate_color!(color) unless color.nil?
        @brand_color = color
      end

      # Overrides of the design tokens (see {Theme::DEFAULTS}), e.g. +{ bg: "#111", radius: "4px" }+.
      def theme=(tokens)
        raise Error::ConfigurationConflict, "config.theme must be a Hash" unless tokens.respond_to?(:to_h)

        normalized = tokens.to_h.transform_keys { |key| key.to_s.to_sym }
        normalized.each { |token, value| Theme.validate_token!(token, value) }
        @theme = normalized.transform_values(&:to_s)
      end

      # +:default+ serves the gem's CSS; a path or URL (or a list of them) replaces it entirely; +nil+ serves none.
      def stylesheet=(reference)
        references = Array(reference)
        references.each { |item| validate_stylesheet!(:stylesheet, item) unless item == :default }
        raise Error::ConfigurationConflict, "config.stylesheet :default cannot be mixed with paths" if references.include?(:default) && references.size > 1

        @stylesheet = reference.is_a?(Array) ? references.freeze : reference
      end

      # Stylesheets loaded after the default (or replacement) one; the place for small adjustments.
      def extra_stylesheets=(references)
        list = Array(references)
        list.each { |item| validate_stylesheet!(:extra_stylesheets, item) }
        @extra_stylesheets = list.freeze
      end

      # @return [Array<String>] the stylesheet URLs of the layout, in order, given the engine's own routes
      def stylesheet_urls(default_url)
        base = stylesheet == :default ? [default_url] : Array(stylesheet)
        base + extra_stylesheets
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

      private

      def validate_stylesheet!(key, reference)
        return if reference.is_a?(String) && reference.match?(STYLESHEET_REFERENCE)

        raise Error::ConfigurationConflict, "config.#{key} takes a path starting with / or an http(s) URL, got #{reference.inspect}"
      end
    end
  end
end
