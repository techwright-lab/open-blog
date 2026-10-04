module OpenBlog
  module Themes
    Preset = Data.define(:name, :light, :dark, :tokens)
    Font = Data.define(:family, :style, :weight, :file, :range)

    MIN_CONTRAST = 4.5

    COLOR_TOKENS = %w[
      surface surface-raised surface-sunken heading text text-muted text-subtle border border-strong
      accent accent-hover accent-soft accent-contrast accent-2 accent-2-soft
      code-bg code-text code-border notice-bg notice-border notice-text note tip warning
    ].freeze

    TOKENS = %w[
      font-display font-body font-mono radius-card radius-media radius-pill prose-size prose-leading
      content-width page-width shadow heading-weight heading-tracking heading-transform rule-width lede-style
    ].freeze

    CONTRAST_PAIRS = [
      %w[heading surface], %w[text surface], %w[text-muted surface], %w[text-subtle surface],
      %w[heading surface-raised], %w[text surface-raised], %w[text-muted surface-raised], %w[text-subtle surface-raised],
      %w[heading surface-sunken], %w[text surface-sunken],
      %w[accent surface], %w[accent-hover surface], %w[accent surface-raised], %w[accent-hover surface-raised], %w[accent accent-soft],
      %w[heading accent-soft], %w[text accent-soft], %w[heading accent-2-soft],
      %w[accent-contrast accent], %w[notice-text notice-bg], %w[code-text code-bg],
      %w[note surface-raised], %w[tip surface-raised], %w[warning surface-raised]
    ].map(&:freeze).freeze

    SANS = "ui-sans-serif, system-ui, sans-serif"
    MONO = '"JetBrains Mono", ui-monospace, SFMono-Regular, Consolas, monospace'

    PRESETS = {
      signal: {
        light: %w[
          #ffffff #f6fbfa #eaf4f2 #0b1f22 #2b3f42 #4d6165 #5f7579 #cfe0dd #5f8a84
          #0f766e #115e59 #d9f0ec #ffffff #b45309 #fdebd3
          #0b1f22 #e6f1ef #0b1f22 #fff7e8 #f0b35b #6b3f0a #1d5fa8 #166534 #92400e
        ],
        dark: %w[
          #071a1c #0d2528 #041214 #eaf6f4 #c9dedb #a3bdb9 #8ba8a4 #1f4145 #5f8a84
          #5eead4 #99f6e4 #0f3d3a #06201f #fbbf24 #3d2a0a
          #041214 #e6f1ef #2a4d51 #33250c #b07d2c #fde7bd #7cc4f8 #86efac #fcd34d
        ],
        tokens: [
          %("Outfit", #{SANS}), %("DM Sans", #{SANS}), MONO, "1rem", "0.75rem", "999px", "1.125rem", "1.8",
          "46rem", "72rem", "0 18px 40px -20px #0b1f2259", "750", "-0.02em", "none", "1px", "normal"
        ]
      },
      editorial: {
        light: %w[
          #fbf7f1 #f4ede2 #ece3d4 #1f1a16 #3a322c #5c524a #6b6158 #dccfbd #8c7b66
          #8a2d2d #6f2222 #f1dedb #ffffff #b7791f #f4e6c9
          #2a2320 #f3ebdf #2a2320 #f6efe4 #d0b58a #5a4420 #2c5282 #2f6b3a #8a5a0b
        ],
        dark: %w[
          #1a1512 #241d18 #120e0c #f6eee2 #ddd2c3 #b9ab9a #a39483 #3d332b #8c7b66
          #e9a09a #f4c2bd #43201e #1a1512 #e0b25a #3a2c10
          #110d0b #f3ebdf #4a3e34 #2e2515 #8a7040 #f0e0be #9cc3e8 #a3d9a5 #ebc46a
        ],
        tokens: [
          '"Newsreader", Georgia, "Times New Roman", serif', '"Newsreader", Georgia, "Times New Roman", serif', MONO,
          "0.375rem", "0.25rem", "999px", "1.25rem", "1.75", "42rem", "72rem", "none", "500", "-0.015em", "none", "1px", "italic"
        ]
      },
      ink: {
        light: %w[
          #ffffff #f5f5f4 #ececea #0a0a0a #262626 #525252 #636363 #d4d4d4 #0a0a0a
          #1f3bd6 #172c9f #e3e8ff #ffffff #c6f432 #f1fbc9
          #0a0a0a #f5f5f5 #0a0a0a #fffbe6 #0a0a0a #0a0a0a #1f3bd6 #166534 #8a4b00
        ],
        dark: %w[
          #000000 #111111 #1a1a1a #ffffff #e5e5e5 #b5b5b5 #9a9a9a #333333 #ffffff
          #8ea2ff #b4c1ff #141c4d #000000 #c6f432 #2a3505
          #0d0d0d #f5f5f5 #ffffff #1f1c05 #ffffff #ffffff #8ea2ff #c6f432 #facc15
        ],
        tokens: [
          %("Space Grotesk", #{SANS}), %("DM Sans", #{SANS}), MONO, "0", "0", "0", "1.0625rem", "1.7",
          "44rem", "72rem", "none", "700", "-0.03em", "uppercase", "2px", "normal"
        ]
      }
    }.to_h do |name, values|
      [ name, Preset.new(name: name, light: COLOR_TOKENS.zip(values[:light]).to_h.freeze,
        dark: COLOR_TOKENS.zip(values[:dark]).to_h.freeze, tokens: TOKENS.zip(values[:tokens]).to_h.freeze) ]
    end.freeze

    RANGES = {
      "latin" => "U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, " \
        "U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD",
      "latin-ext" => "U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, " \
        "U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF"
    }.freeze

    FONTS = [
      [ "Outfit", "normal", "100 900", "outfit" ],
      [ "DM Sans", "normal", "100 1000", "dm-sans" ],
      [ "DM Sans", "italic", "100 1000", "dm-sans-italic" ],
      [ "JetBrains Mono", "normal", "100 800", "jetbrains-mono" ],
      [ "Newsreader", "normal", "200 800", "newsreader" ],
      [ "Newsreader", "italic", "200 800", "newsreader-italic" ],
      [ "Space Grotesk", "normal", "300 700", "space-grotesk" ]
    ].flat_map do |family, style, weight, file|
      RANGES.map { |subset, range| Font.new(family: family, style: style, weight: weight, file: "#{file}-#{subset}.woff2", range: range) }
    end.freeze

    HEX = /\A#(?:\h{3}|\h{6}|\h{8})\z/

    class << self
      def names
        PRESETS.keys
      end

      def fetch(name)
        PRESETS.fetch(name.to_s.to_sym) do
          raise ConfigurationError, "Unknown theme #{name.inspect}; use #{names.join(', ')}"
        end
      end

      def css(name, light: {}, dark: {})
        root = %(:root[data-ob-theme="#{fetch(name).name}"])
        system = "@media (prefers-color-scheme: dark) {\n#{rule(%(#{root}:not([data-theme="light"])), dark, "  ")}}\n"
        [
          (rule(root, light) if light.any?),
          (rule(%(#{root}[data-theme="dark"]), dark) if dark.any?),
          (system if dark.any?)
        ].compact.join
      end

      def contrast(foreground, background, backdrop = background)
        under = blend(rgba(background), rgba(backdrop).first(3))
        lighter, darker = [ blend(rgba(foreground), under), under ].map { |color| luminance(color) }.sort.reverse
        (lighter + 0.05) / (darker + 0.05)
      end

      def low_contrast(colors)
        CONTRAST_PAIRS.filter_map do |foreground, background|
          ratio = contrast(colors.fetch(foreground), colors.fetch(background), colors.fetch("surface"))
          [ foreground, background, ratio ] if ratio < MIN_CONTRAST
        end
      end

      private

      def rule(selector, values, indent = "")
        lines = values.map { |token, value| "#{indent}  --ob-#{token.to_s.tr('_', '-')}: #{value};\n" }
        "#{indent}#{selector} {\n#{lines.join}#{indent}}\n"
      end

      def rgba(color)
        raise ArgumentError, "Expected a hex colour, got #{color.inspect}" unless color.is_a?(String) && color.match?(HEX)
        digits = color.delete_prefix("#")
        digits = digits.chars.map { |digit| digit * 2 }.join if digits.length == 3
        digits.ljust(8, "f").scan(/../).map { |channel| channel.to_i(16) / 255.0 }
      end

      def blend(color, under)
        *channels, alpha = color
        channels.zip(under).map { |top, bottom| top * alpha + bottom * (1 - alpha) }
      end

      def luminance(channels)
        channels.zip([ 0.2126, 0.7152, 0.0722 ]).sum do |value, weight|
          weight * (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4)
        end
      end
    end
  end
end
