require_relative "../application_system_test_case"
require "zlib"

class ReaderBrowserTest < ApplicationSystemTestCase
  setup do
    @original_config = OpenBlog.config
    OpenBlog.instance_variable_set(:@config, @original_config.deep_dup)
    OpenBlog.config.color_scheme = :system
    OpenBlog.config.image_delivery = :proxy
    @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(wide_png), filename: "garden.png", content_type: "image/png", identify: false)
    image = OpenBlog::Image.new(sha256: Digest::SHA256.hexdigest(wide_png), filename: "garden.png", content_type: "image/png", byte_size: @blob.byte_size, width: 1200, height: 300)
    image.file = @blob
    image.save!
    author = OpenBlog::Author.create!(name: "Ellis River", slug: "ellis-river", bio: "Notes from a home garden.")
    category = OpenBlog::Category.create!(name: "Home gardens", slug: "home-gardens")
    @post = OpenBlog::Post.create!(title: "A garden through the seasons", slug: "garden-seasons", description: "Simple care for a small garden.",
      author: author, author_name: author.name, category: category, cover_image: image, cover_alt: "A green planting bed",
      body_markdown: "![A green planting bed](#{image.path})\n\n#{article_body}", status: "published", featured: true)
    @post.tags << OpenBlog::Tag.create!(name: "Outdoors", slug: "outdoors")
    [ "Choosing a planter", "Watering young roots", "Saving seeds for spring" ].each_with_index do |title, index|
      OpenBlog::Post.create!(title: title, slug: title.parameterize, description: "A practical note for your next afternoon outdoors.",
        author: author, author_name: author.name, category: category, body_markdown: "Start small and observe how your plants respond.",
        cover_image: index < 2 ? image : nil, cover_alt: index < 2 ? "A green planting bed" : "", status: "published")
    end
    @paths = [ "/blog", @post.path, "/blog/category/home-gardens", "/blog/tag/outdoors", "/blog/author/ellis-river", "/blog/missing-page" ]
    visit "/blog"
    page.execute_script("localStorage.clear()")
    system_theme("light")
  end

  teardown do
    OpenBlog.instance_variable_set(:@config, @original_config)
    @blob&.service&.delete(@blob.key)
  end

  test "theme cycles persists and respects a fixed publisher choice" do
    visit @post.path
    button = find(".ob-theme-toggle")
    assert_includes button.text, "System"
    button.click
    assert_selector "html[data-theme=light]"
    assert_equal "light", page.evaluate_script("localStorage.getItem('open-blog-theme')")
    button.click
    assert_selector "html[data-theme=dark]"
    page.refresh
    assert_selector "html[data-theme=dark]"
    find(".ob-theme-toggle").click
    assert_no_selector "html[data-theme]"
    assert_nil page.evaluate_script("localStorage.getItem('open-blog-theme')")
    OpenBlog.config.color_scheme = :dark
    visit @post.path
    assert_selector "html[data-theme=dark]"
    assert_no_selector ".ob-theme-toggle", visible: :all
    assert_no_selector "script[data-open-blog-theme]", visible: :all
  end

  test "saved dark choice is present before stylesheet insertion and first frame" do
    before_navigation <<~JS
      localStorage.setItem('open-blog-theme', 'dark');
      window.themeObservations = [];
      window.earlyThemeChanges = [];
      new MutationObserver(records => {
        for (const record of records) {
          if (record.type === 'attributes' && record.target === document.documentElement) {
            window.earlyThemeChanges.push({ theme: record.target.dataset.theme, stylesheets: document.querySelectorAll('link[rel="stylesheet"]').length });
          }
          for (const node of record.addedNodes) {
            if (node.nodeType === 1 && node.matches('link[rel="stylesheet"]')) {
              window.themeObservations.push({ theme: document.documentElement.dataset.theme });
            }
          }
        }
      }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-theme'] });
      document.addEventListener('DOMContentLoaded', () => {
        window.domReadyTheme = document.documentElement.dataset.theme;
        requestAnimationFrame(() => { window.firstFrameBackground = getComputedStyle(document.body).backgroundColor; });
      });
    JS
    visit @post.path
    assert_selector "html[data-theme=dark]"
    observations = page.evaluate_script("window.themeObservations")
    assert observations.any?, "No stylesheet observed"
    assert_equal "dark", observations.first.fetch("theme")
    assert_equal({ "theme" => "dark", "stylesheets" => 0 }, page.evaluate_script("window.earlyThemeChanges[0]"))
    assert_equal "dark", page.evaluate_script("window.domReadyTheme")
    assert_equal "rgb(15, 23, 42)", page.evaluate_script("window.firstFrameBackground")
  end

  test "blocked storage leaves a usable theme control and content" do
    before_navigation <<~JS
      Object.defineProperty(window, 'localStorage', { get() { throw new DOMException('Storage blocked', 'SecurityError'); } });
    JS
    visit @post.path
    assert_selector "h1", text: @post.title
    find(".ob-theme-toggle").click
    assert_selector "html[data-theme=light]"
    find(".ob-theme-toggle").click
    assert_selector "html[data-theme=dark]"
  end

  test "unsupported sharing stays hidden and invalid stored themes do not survive reconnect" do
    before_navigation <<~JS
      localStorage.setItem('open-blog-theme', 'unexpected-value');
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined });
      Object.defineProperty(navigator, 'share', { configurable: true, value: undefined });
    JS
    visit @post.path
    assert_selector ".ob-theme-toggle", text: "System"
    assert_no_selector "html[data-theme]"
    assert_no_selector ".ob-share-button"
    assert_no_selector ".ob-code-copy"
    page.execute_script("window.savedThemeControl = document.querySelector('.ob-theme-toggle'); window.savedThemeControl.remove()")
    page.execute_script("document.querySelector('.ob-header').append(window.savedThemeControl)")
    find(".ob-theme-toggle").click
    assert_selector "html[data-theme=light]"
    page.execute_script("window.savedShareControl = document.querySelector('.ob-share'); window.savedShareControl.remove()")
    page.execute_script("document.querySelector('.ob-post').append(window.savedShareControl)")
    assert_selector '.ob-share [data-open-blog--share-target="copy"] svg', visible: :all
  end

  test "share cancellation is quiet and clipboard failure is announced" do
    before_navigation <<~JS
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => { throw new Error('Clipboard blocked'); } } });
      Object.defineProperty(navigator, 'share', { configurable: true, value: async () => { throw new DOMException('Cancelled', 'AbortError'); } });
    JS
    visit @post.path
    find('.ob-share [data-open-blog--share-target="device"]').click
    assert_selector ".ob-share-status", exact_text: "", visible: :all
    find('.ob-share [data-open-blog--share-target="copy"]').click
    assert_selector ".ob-share-status", text: I18n.t("open_blog.share.failed")
    assert_selector '[data-open-blog--share-target="copy"]', text: "Copy link"
  end

  test "every reader page fits narrow and wide viewports and passes accessibility in both themes" do
    %w[light dark].each do |theme|
      page.execute_script("localStorage.setItem('open-blog-theme', arguments[0])", theme)
      [ 320, 1280 ].each do |width|
        viewport(width)
        @paths.each do |path|
          visit path
          assert_selector "h1", count: 1
          assert_selector ".ob-post-grid .ob-post-card", count: 3 if path == "/blog"
          assert_selector ".ob-related-posts .ob-post-card", count: 3 if path == @post.path
          assert_selector "html[data-theme='#{theme}']"
          assert_equal width, page.evaluate_script("innerWidth")
          assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth"), "#{path}, #{theme}, #{width}px overflows"
          assert page.evaluate_async_script(<<~JS), "#{path}: an image failed to load"
            const done = arguments[arguments.length - 1];
            const start = [window.scrollX, window.scrollY];
            (async () => {
              let loaded = true;
              for (const image of document.images) {
                image.scrollIntoView({ block: 'center' });
                loaded = await image.decode().then(() => image.naturalWidth > 0).catch(() => false) && loaded;
              }
              window.scrollTo(...start);
              requestAnimationFrame(() => done(loaded));
            })();
          JS
          assert_accessible
          if (path == "/blog" && width == 1280) || (path == @post.path && width == 320)
            name = path == "/blog" ? "index-desktop" : "post-mobile"
            save_screenshot(Rails.root.join("tmp/capybara/reader-#{name}-#{theme}.png"))
          end
        end
      end
    end
  end

  test "disabled JavaScript preserves navigation and follows the system color preference" do
    cdp("Emulation.setScriptExecutionDisabled", value: true)
    %w[light dark].each do |theme|
      system_theme(theme)
      @paths.each do |path|
        visit path
        assert_selector "h1", count: 1
        assert_no_selector ".ob-theme-toggle"
        assert_no_selector ".ob-share-button"
        assert_no_selector ".ob-code-copy"
        assert_equal(theme == "dark" ? "rgb(15, 23, 42)" : "rgb(255, 255, 255)", page.evaluate_script("getComputedStyle(document.body).backgroundColor"))
        find(".ob-header a", match: :first).click
        assert_current_path "/blog"
      end
    end
    visit @post.path
    assert_selector "[data-open-blog-body]", text: "Preparing the soil"
    find(".ob-toc a", match: :first).click
    assert_includes current_url, "#preparing-the-soil"
  end

  test "copy share table of contents and reading progress work through real controllers" do
    before_navigation <<~JS
      window.copiedValues = [];
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async value => { window.copiedValues.push(value); } } });
      Object.defineProperty(navigator, 'share', { configurable: true, value: async value => { window.sharedValue = value; } });
    JS
    visit @post.path
    copy = find('.ob-share [data-open-blog--share-target="copy"]')
    copied_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    copy.click
    assert_equal OpenBlog.config.public_base_url + @post.path, page.evaluate_script("window.copiedValues[0]")
    assert_selector ".ob-share", text: "Copied!"
    assert_no_selector ".ob-share-status", text: "Copied!", wait: 4
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - copied_at, :>=, 1.8
    find('[data-open-blog--code-copy-target="button"]').click
    assert_equal "puts \"green\"\n", page.evaluate_script("window.copiedValues[1]")
    find('.ob-share [data-open-blog--share-target="device"]').click
    assert_equal @post.title, page.evaluate_script("window.sharedValue.title")
    page.execute_script("window.scrollTo(0, 0)")
    assert_selector '.ob-reading-progress-fill[style*="width: 0%"]', visible: :all
    initial = page.evaluate_script("parseFloat(document.querySelector('.ob-reading-progress-fill').style.width) || 0")
    find('.ob-toc a[href="#winter-plans"]').click
    assert_selector '.ob-toc a[href="#winter-plans"][aria-current="location"]'
    progressed = page.evaluate_script("parseFloat(document.querySelector('.ob-reading-progress-fill').style.width)")
    assert_operator progressed, :>, initial
  end

  private

  def wide_png
    @wide_png ||= begin
      chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
      header = [ 1200, 300, 8, 2, 0, 0, 0 ].pack("NNC5")
      pixels = ("\0" + "\x6b\x8e\x23".b * 1200) * 300
      "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", header) + chunk.call("IDAT", Zlib.deflate(pixels)) + chunk.call("IEND", "")
    end
  end

  def article_body
    paragraphs = ([ "Watch the leaves and water the roots. Give every plant enough room to grow." ] * 12).join("\n\n")
    "## Preparing the soil\n\n#{paragraphs}\n\n```ruby\nputs \"green\"\n```\n\n" \
      "| Planter | Care notes |\n| --- | --- |\n| #{'Longplantername' * 10} | Water when dry |\n\n" \
      "## Summer growth\n\n#{paragraphs}\n\n## Winter plans\n\n#{paragraphs}"
  end
end
