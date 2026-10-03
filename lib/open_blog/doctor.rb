require "net/http"
require "securerandom"
require "timeout"
require_relative "doctor/files"
require_relative "doctor/javascript"

module OpenBlog
  class Doctor
    include Files
    include Javascript

    CHECKS = { "Configuration" => :configuration, "Migrations" => :migrations, "Route" => :route,
      "Views" => :views, "Theme" => :theme, "JavaScript" => :javascript, "Authentication" => :authentication,
      "Rate limit" => :rate_limit, "Jobs" => :jobs, "Storage" => :storage, "Policy pages" => :policy_pages,
      "Records" => :records, "Declarations" => :declarations }.freeze
    TABLES = %w[open_blog_authors open_blog_categories open_blog_series open_blog_images open_blog_posts
      open_blog_faqs open_blog_tags open_blog_taggings open_blog_redirects open_blog_revisions
      open_blog_approvals open_blog_publications open_blog_baselines open_blog_connection_declarations
      active_storage_blobs active_storage_attachments active_storage_variant_records action_text_rich_texts].freeze

    def self.run(application: Rails.application, config: OpenBlog.config, http_get: nil)
      new(application: application, config: config, http_get: http_get).run
    end

    def initialize(application:, config:, http_get:)
      @application, @config, @http_get = application, config, http_get
      @root = application.root
    end

    def run
      CHECKS.map do |name, method|
        status, message = send(method)
        { name: name, status: status, message: message }
      rescue StandardError => error
        { name: name, status: "error", message: "Check unavailable: #{error.class}: #{error.message}" }
      end
    end

    private

    def configuration
      @config.validate!
      values = [ @config.site_name, @config.default_author&.dig(:name), @config.publisher&.dig(:name) ]
      return [ "warning", "Replace installer placeholder names." ] if (values & [ "Example", "Ada Example" ]).any?
      [ "ok", "Required configuration is present." ]
    rescue ConfigurationError => error
      [ "error", error.message ]
    end

    def missing_tables
      @missing_tables ||= TABLES.reject { |name| ActiveRecord::Base.connection.data_source_exists?(name) }
    end

    def migrations
      return [ "error", "Missing tables: #{missing_tables.join(', ')}. Run the installed migrations." ] if missing_tables.any?
      pool = ActiveRecord::Base.connection_pool
      paths = @application.paths["db/migrate"].existent
      context = ActiveRecord::MigrationContext.new(paths, pool.schema_migration, pool.internal_metadata)
      expected = Dir[Engine.root.join("db/migrate/*.rb")].map { |path| File.basename(path).sub(/\A\d+_/, "").delete_suffix(".rb").camelize }
      installed = context.migrations.select { |migration| expected.include?(migration.name) }
      absent = expected - installed.map(&:name)
      pending = installed.reject { |migration| context.get_all_versions.include?(migration.version) }.map(&:name)
      return [ "error", "Install and run migrations: #{(absent + pending).join(', ')}." ] if absent.any? || pending.any?
      [ "ok", "Content, Active Storage and Action Text migrations are installed." ]
    end

    def route
      routes = @application.routes.routes.to_a
      index = routes.index { |candidate| candidate.app.respond_to?(:app) && candidate.app.app == Engine }
      return [ "error", "Mount OpenBlog::Engine after host routes under its path." ] unless index
      prefix = routes[index].path.spec.to_s.sub(/\(.*\z/, "").chomp("/")
      shadowed = routes.drop(index + 1).filter_map do |candidate|
        path = candidate.path.spec.to_s.sub(/\(.*\z/, "")
        path if path == prefix || path.start_with?("#{prefix}/")
      end
      return [ "error", "Move the engine mount after these host routes: #{shadowed.join(', ')}." ] if shadowed.any?
      [ "ok", "Engine mounted at #{prefix.presence || '/'} after matching host routes." ]
    end

    def authentication
      @config.authenticate ? [ "ok", "Host authentication hook is configured." ] : [ "warning", "No host authentication hook or API token is configured." ]
    end

    def rate_limit
      key = "open-blog-doctor-#{SecureRandom.hex(12)}"
      store = @config.rate_limit_store
      store.write(key, 0, raw: true, expires_in: 30.seconds)
      value = store.increment(key, 1)
      value == 1 ? [ "ok", "Rate limit store supports increment." ] : [ "warning", "Rate limit store cannot count; configure a store with atomic increment." ]
    rescue NotImplementedError, StandardError
      [ "warning", "Rate limit store cannot count; configure a store with atomic increment." ]
    ensure
      store&.delete(key)
    end

    def jobs
      adapter = @application.config.active_job.queue_adapter.to_s
      if %w[async inline test].include?(adapter)
        [ "warning", "#{adapter} jobs do not survive restart; use a persistent adapter and arrange open_blog:publish_due for scheduled posts." ]
      else
        [ "ok", "Job adapter is #{adapter}." ]
      end
    end

    def storage
      service = @config.storage_service || @application.config.active_storage.service
      return [ "error", "Configure an Active Storage service." ] unless service
      ActiveStorage::Blob.services.fetch(service)
      return [ "error", "Install image_processing for reader image variants." ] unless Gem.loaded_specs.key?("image_processing")
      processor = @application.config.active_storage.variant_processor || :vips
      if processor.to_sym == :vips
        begin
          require "vips"
        rescue LoadError
          return [ "error", "Install ruby-vips and libvips for the configured image processor." ]
        end
      elsif !ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |directory| %w[magick identify].any? { |name| File.executable?(File.join(directory, name)) } }
        return [ "error", "Install ImageMagick for the configured image processor." ]
      end
      return [ "warning", "Image URL address protection is disabled (image_fetch_policy = :open)." ] if @config.image_fetch_policy == :open
      [ "ok", "Active Storage and the configured image processor are available." ]
    end

    def policy_pages
      problems = %i[responsible_party corrections editorial ai_use].filter_map do |key|
        url = @config.policy_urls[key]
        next "#{key}: no URL configured" if url.blank?
        begin
          code = @http_get ? @http_get.call(url).to_i : policy_response(url)
          "#{key}: HTTP #{code}" unless code == 200
        rescue StandardError => error
          "#{key}: unavailable (#{error.class})"
        end
      end
      problems.any? ? [ "warning", problems.join("; ") ] : [ "ok", "All policy URLs respond with HTTP 200." ]
    end

    def policy_response(url)
      uri = URI.parse(url)
      raise ArgumentError unless uri.is_a?(URI::HTTP) && uri.host && uri.userinfo.nil?
      Timeout.timeout(3) do
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 2, read_timeout: 2) do |http|
          http.request(Net::HTTP::Get.new(uri)) { |response| return response.code.to_i }
        end
      end
    end

    def records
      return [ "warning", "Records cannot be checked until all content tables are installed." ] if missing_tables.any?
      problems = []
      Post.where(status: "published").find_each do |post|
        revision = post.public_revision
        problems << "#{post.id}: content differs from public revision" unless revision && RevisionPayload.new(post).identifier == revision.identifier
        published = post.publications.find_by(entry_type: "first")&.occurred_at || post.baseline&.first_published_at || post.baseline&.declared_first_published_at
        modified = post.publications.where(entry_type: %w[substantive correction]).maximum(:occurred_at) || post.baseline&.last_modified_at || published
        problems << "#{post.id}: modified_at differs from publication records" unless post.modified_at == modified
      end
      problems.any? ? [ "error", problems.join("; ") ] : [ "ok", "Public content and modification dates match their records." ]
    end

    def declarations
      source = read("config/initializers/open_blog.rb")
      absent = %i[primary_list_type sign_in_destinations].reject do |name|
        !@config.public_send(name).nil? && source.match?(/\.#{name}\s*=/)
      end
      absent.any? ? [ "warning", "Declare #{absent.join(' and ')} in the blog initializer." ] : [ "ok", "List type and sign-in destinations are declared." ]
    end
  end
end
