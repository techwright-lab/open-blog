require_relative "test_helper"

class ThemeContrastTest < ActiveSupport::TestCase
  Themes = OpenBlog::Themes

  Themes.names.each do |name|
    %i[light dark].each do |mode|
      Themes::CONTRAST_PAIRS.each do |foreground, background|
        test "#{name} #{mode}: #{foreground} on #{background} meets AA" do
          colors = Themes.fetch(name).public_send(mode)
          ratio = Themes.contrast(colors.fetch(foreground), colors.fetch(background))
          assert_operator ratio, :>=, Themes::MIN_CONTRAST,
            "#{colors.fetch(foreground)} on #{colors.fetch(background)} gives #{ratio.round(3)}"
        end
      end
    end
  end

  test "three presets ship and signal is first" do
    assert_equal %i[signal editorial ink], Themes.names
    assert_same Themes.fetch(:ink), Themes.fetch("ink")
    error = assert_raises(OpenBlog::ConfigurationError) { Themes.fetch(:slate) }
    assert_includes error.message, "signal, editorial, ink"
  end

  test "every preset defines every token once with a valid value and is frozen" do
    assert_equal 24, Themes::COLOR_TOKENS.length
    assert_empty %w[accent-2 accent-2-soft code-text] - Themes::COLOR_TOKENS
    assert_empty %w[heading-weight heading-tracking heading-transform rule-width lede-style shadow] - Themes::TOKENS
    Themes.names.each do |name|
      preset = Themes.fetch(name)
      [ preset.light, preset.dark ].each do |colors|
        assert_equal Themes::COLOR_TOKENS, colors.keys
        colors.each { |token, value| assert_match(/\A#\h{6}\z/, value, "#{name} #{token}") }
        assert_predicate colors, :frozen?
      end
      assert_equal Themes::TOKENS, preset.tokens.keys
      preset.tokens.each { |token, value| assert_predicate value, :present?, "#{name} #{token}" }
      assert_predicate preset.tokens, :frozen?
      refute_equal preset.light.fetch("surface"), preset.dark.fetch("surface")
    end
    assert_predicate Themes::PRESETS, :frozen?
  end

  test "the mock light values and the character of each dark preset are kept" do
    assert_equal %w[#ffffff #0f766e #b45309], Themes.fetch(:signal).light.values_at("surface", "accent", "accent-2")
    assert_equal %w[#fbf7f1 #8a2d2d], Themes.fetch(:editorial).light.values_at("surface", "accent")
    assert_equal %w[#ffffff #1f3bd6 #c6f432], Themes.fetch(:ink).light.values_at("surface", "accent", "accent-2")
    assert_equal %w[#000000 #c6f432], Themes.fetch(:ink).dark.values_at("surface", "accent-2")
    assert_equal %w[#0b1f22 #e6f1ef #0b1f22], Themes.fetch(:signal).light.values_at("code-bg", "code-text", "code-border")
    assert_equal %w[#2a2320 #f3ebdf #2a2320], Themes.fetch(:editorial).light.values_at("code-bg", "code-text", "code-border")
    assert_equal %w[#0a0a0a #f5f5f5 #0a0a0a], Themes.fetch(:ink).light.values_at("code-bg", "code-text", "code-border")
    assert_equal "uppercase", Themes.fetch(:ink).tokens.fetch("heading-transform")
    assert_equal "italic", Themes.fetch(:editorial).tokens.fetch("lede-style")
    assert_equal "2px", Themes.fetch(:ink).tokens.fetch("rule-width")
  end

  test "every contrast pair names known colour tokens" do
    assert_empty Themes::CONTRAST_PAIRS.flatten - Themes::COLOR_TOKENS
    [ %w[accent-contrast accent], %w[notice-text notice-bg], %w[code-text code-bg], %w[accent surface],
      %w[text-subtle surface-raised], %w[warning surface-raised] ].each { |pair| assert_includes Themes::CONTRAST_PAIRS, pair }
  end

  test "contrast follows the WCAG formula for every accepted hex form" do
    assert_in_delta 21.0, Themes.contrast("#000000", "#ffffff"), 0.001
    assert_in_delta 21.0, Themes.contrast("#fff", "#000"), 0.001
    assert_in_delta 1.0, Themes.contrast("#1d4ed8", "#1D4ED8ff"), 0.001
    assert_in_delta 4.542, Themes.contrast("#767676", "#ffffff"), 0.001
    assert_raises(ArgumentError) { Themes.contrast("white", "#000000") }
  end

  test "a translucent colour is measured as it shows over what is under it" do
    assert_in_delta 1.0, Themes.contrast("#00000000", "#ffffff"), 0.001
    assert_in_delta 21.0, Themes.contrast("#000000ff", "#ffffff"), 0.001
    assert_in_delta Themes.contrast("#7f7f7f", "#ffffff"), Themes.contrast("#00000080", "#ffffff"), 0.02
    assert_in_delta 1.0, Themes.contrast("#ffffff", "#00000000", "#ffffff"), 0.001
    assert_in_delta 21.0, Themes.contrast("#ffffff", "#00000000", "#000000"), 0.001
    colors = Themes.fetch(:signal).light
    assert_equal [ %w[text surface], %w[text surface-raised], %w[text surface-sunken], %w[text accent-soft] ],
      Themes.low_contrast(colors.merge("text" => "#2b3f4200")).map { |row| row.first(2) }
    assert_equal [ %w[notice-text notice-bg] ], Themes.low_contrast(colors.merge("notice-bg" => "#6b3f0a")).map { |row| row.first(2) }
    assert_empty Themes.low_contrast(colors.merge("notice-bg" => "#6b3f0a00"))
  end

  test "low contrast lists each failing pair of a colour set with its ratio" do
    colors = Themes.fetch(:signal).light
    assert_empty Themes.low_contrast(colors)
    failures = Themes.low_contrast(colors.merge("accent" => "#99f6e4"))
    assert_equal [ %w[accent surface], %w[accent surface-raised], %w[accent accent-soft], %w[accent-contrast accent] ], failures.map { |row| row.first(2) }
    failures.each { |row| assert_operator row.last, :<, Themes::MIN_CONTRAST }
  end

  test "rule blocks render partial light and dark values under the three selectors" do
    css = Themes.css(:editorial, light: { accent: "#1d4ed8", "accent-2" => "#0f766e" }, dark: { accent_2: "#93c5fd" })
    assert_equal <<~CSS, css
      :root[data-ob-theme="editorial"] {
        --ob-accent: #1d4ed8;
        --ob-accent-2: #0f766e;
      }
      :root[data-ob-theme="editorial"][data-theme="dark"] {
        --ob-accent-2: #93c5fd;
      }
      @media (prefers-color-scheme: dark) {
        :root[data-ob-theme="editorial"]:not([data-theme="light"]) {
          --ob-accent-2: #93c5fd;
        }
      }
    CSS
    assert_equal "", Themes.css(:ink)
    refute_includes Themes.css(:ink, light: { surface: "#fafafa" }), "prefers-color-scheme"
    refute_includes Themes.css(:ink, dark: { surface: "#111111" }), ":root[data-ob-theme=\"ink\"] {"
    assert_raises(OpenBlog::ConfigurationError) { Themes.css(:slate, light: { surface: "#ffffff" }) }
  end
end
