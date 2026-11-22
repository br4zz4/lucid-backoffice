require "digest"

module Lucid
  module Backoffice
    # Design tokens of the panel. The default look is black with a lime accent; every token is a CSS custom
    # property (+--lb-<token>+) that an app overrides with +config.theme+ and +config.brand_color+, or replaces
    # together with the whole stylesheet through +config.stylesheet+.
    module Theme
      DEFAULTS = {
        bg: "#000",
        surface: "#0a0a0a",
        raised: "#141414",
        border: "rgb(255 255 255 / .1)",
        text: "#f2f2f4",
        muted: "#8b8b93",
        accent: "#c6ff00",
        on_accent: "#000",
        ok: "#c6ff00",
        warn: "#f5b942",
        danger: "#ff5d5d",
        font_sans: '"Inter Variable", Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
        font_mono: '"JetBrains Mono Variable", "JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace',
        radius: "12px"
      }.freeze

      TOKENS = DEFAULTS.keys.freeze
      HEX_COLOR = /\A#(\h{3}|\h{6})\z/
      SAFE_VALUE = %r{\A[\w #%.,()/"'-]+\z}
      FORBIDDEN_FRAGMENTS = /url\(|expression\(|@import|javascript:/i
      CONTRAST_CROSSOVER = 0.179

      class << self
        # @raise [Error::ConfigurationConflict] when the token is unknown or the value could break out of a declaration
        def validate_token!(token, value)
          raise Error::ConfigurationConflict, "config.theme has no token #{token.inspect}; known: #{TOKENS.join(", ")}" unless TOKENS.include?(token)

          text = value.to_s
          return if text.match?(SAFE_VALUE) && !text.match?(FORBIDDEN_FRAGMENTS)

          raise Error::ConfigurationConflict, "config.theme[#{token.inspect}] #{value.inspect} is not a plain CSS value"
        end

        # @raise [Error::ConfigurationConflict] unless the color is +#rgb+ or +#rrggbb+
        def validate_color!(value)
          return if value.is_a?(String) && value.match?(HEX_COLOR)

          raise Error::ConfigurationConflict, "config.brand_color must be #rgb or #rrggbb, got #{value.inspect}"
        end

        # @return [Hash{Symbol=>String}] defaults, then +brand_color+ (with a readable text color), then +theme+
        def tokens(configuration = Lucid::Backoffice.configuration)
          resolved = DEFAULTS.dup
          if configuration.brand_color
            resolved[:accent] = configuration.brand_color
            resolved[:on_accent] = contrast_for(configuration.brand_color)
          end
          resolved.merge(configuration.theme)
        end

        # @return [String] the +.lb+ rule that sets every token
        def css(configuration = Lucid::Backoffice.configuration)
          declarations = tokens(configuration).map { |token, value| "--lb-#{token.to_s.tr("_", "-")}:#{value}" }
          ".lb{#{declarations.join(";")}}\n"
        end

        def digest(configuration = Lucid::Backoffice.configuration)
          Digest::SHA256.hexdigest(css(configuration))[0, 12]
        end

        # @return [String] +#000+ or +#fff+, whichever reads better over the given hex color
        def contrast_for(hex)
          digits = hex.delete("#")
          digits = digits.chars.map { |char| char * 2 }.join if digits.length == 3
          red, green, blue = digits.scan(/../).map { |pair| linear(pair.hex / 255.0) }
          (0.2126 * red + 0.7152 * green + 0.0722 * blue) > CONTRAST_CROSSOVER ? "#000" : "#fff"
        end

        private

        def linear(channel)
          channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
        end
      end
    end
  end
end
