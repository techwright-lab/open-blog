require_relative "test_helper"
require "capybara/rails"
require "selenium-webdriver"
require "digest"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ] do |options|
    options.add_argument("no-sandbox")
    options.add_argument("disable-dev-shm-usage")
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"].present?
  end

  Capybara.server = :puma, { Silent: true }
  Capybara.default_max_wait_time = 5

  def cdp(command, **parameters)
    page.driver.browser.execute_cdp(command, **parameters)
  end

  def viewport(width, height = 900)
    cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
  end

  def system_theme(value)
    cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: value } ])
  end

  def before_navigation(source)
    result = cdp("Page.addScriptToEvaluateOnNewDocument", source: source)
    @document_scripts ||= []
    @document_scripts << result.fetch("identifier")
  end

  def assert_accessible
    source = File.binread(File.expand_path("support/axe.min.js", __dir__))
    assert_equal "c24f097bd2f451d4f933e8bc7d8d539f8672a2ebcb5cc9f9f3eec8ca9470a0c1", Digest::SHA256.hexdigest(source)
    page.execute_script(source)
    violations = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'] } })
        .then(result => done(result.violations.map(item => ({ id: item.id, impact: item.impact, nodes: item.nodes.map(node => node.target) }))))
        .catch(error => done([{ error: error.message }]));
    JS
    assert_empty violations, "#{current_path}: #{violations.inspect}"
  end

  teardown do
    if Capybara.current_session&.driver&.browser
      cdp("Emulation.setScriptExecutionDisabled", value: false)
      cdp("Emulation.clearDeviceMetricsOverride")
      cdp("Emulation.setEmulatedMedia", features: [])
      Array(@document_scripts).each { |identifier| cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: identifier) }
    end
  end
end
