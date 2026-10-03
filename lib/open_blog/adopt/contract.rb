module OpenBlog
  class Adopt
    class Contract
      CONTENT_FIELDS = (PostAttributes::CONTENT_FIELDS + %i[provenance provenance_evidence]).freeze
      EXTRA_FIELDS = %i[source_system source_id source_body_sha256 old_slugs category_description first_published_at first_published_evidence last_modified_at last_modified_evidence imported_approval declaration connections dry_run].freeze
      attr_reader :attributes, :baseline, :approval, :connections

      def initialize(input, now: Time.current)
        @now = now
        invalid("attributes") unless input.is_a?(Hash) && input.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
        @attributes = input.symbolize_keys
        unknown = @attributes.keys - CONTENT_FIELDS - EXTRA_FIELDS
        raise Error::UnknownField.new(details: unknown.map(&:to_s)) if unknown.any?
        %i[source_system source_id slug title body_format].each { |field| required_text(@attributes, field, field.to_s) }
        invalid("body") unless @attributes[:body].is_a?(String)
        raise Error::SlugNotSupported.new(details: [ "slug" ]) unless Post::SLUG_PATTERN.match?(@attributes[:slug])
        invalid("dry_run") if @attributes.key?(:dry_run) && ![ true, false ].include?(@attributes[:dry_run])
        %i[category_description provenance_evidence first_published_evidence last_modified_evidence].each do |field|
          invalid(field.to_s) if @attributes.key?(field) && !@attributes[field].nil? && !@attributes[field].is_a?(String)
        end
        if !@attributes[:source_body_sha256].nil? && !(@attributes[:source_body_sha256].is_a?(String) && @attributes[:source_body_sha256].match?(/\A[0-9a-f]{64}\z/))
          invalid("source_body_sha256")
        end
        normalize_approval
        normalize_baseline
        normalize_connections
      end

      def dry_run?
        @attributes[:dry_run] == true
      end

      def content
        defaults = { description: "", search_title: "", search_description: "", cover_alt: "", faq: [], tags: [],
          category: nil, series: nil, series_position: nil, featured: false, canonical_url: nil, external_id: nil,
          cover_image: nil, social_image: nil, author: OpenBlog.config.default_author, provenance: "unknown", provenance_evidence: nil }
        defaults.merge(@attributes.slice(*CONTENT_FIELDS)).merge(provenance: @baseline[:provenance], provenance_evidence: @baseline[:provenance_evidence])
      end

      def redirects(default_date:, current_slug:)
        value = @attributes.fetch(:old_slugs, [])
        invalid("old_slugs") unless value.is_a?(Array)
        value.map do |item|
          entry = item.is_a?(String) ? { slug: item } : nested(item, %i[slug moved_on], "old_slugs")
          slug = required_text(entry, :slug, "old_slugs.slug")
          unless Post::SLUG_PATTERN.match?(slug)
            raise Error::SlugNotSupported.new(details: [ "old_slugs.slug" ])
          end
          invalid("old_slugs.slug") if slug == current_slug
          { old_path: "#{OpenBlog.mount_path.chomp('/')}/#{slug}", new_path: "#{OpenBlog.mount_path.chomp('/')}/#{current_slug}",
            occurred_on: entry[:moved_on].nil? ? default_date : date(entry[:moved_on], "old_slugs.moved_on") }
        end.uniq.sort_by { |entry| entry[:old_path] }
      end

      private

      def invalid(field)
        raise Error::ValidationFailed.new(details: Array(field))
      end

      def required_text(input, field, path)
        value = input[field]
        invalid(path) unless value.is_a?(String) && value.present?
        value
      end

      def nested(value, allowed, path)
        invalid(path) unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
        result = value.symbolize_keys
        unknown = result.keys - allowed
        raise Error::UnknownField.new(details: unknown.map { |field| "#{path}.#{field}" }) if unknown.any?
        result
      end

      def timestamp(value, path)
        return if value.nil?
        invalid(path) unless value.is_a?(String) || value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) || value.is_a?(DateTime)
        result = value.is_a?(String) ? Time.iso8601(value) : value.to_time
        result.utc.floor(6)
      rescue ArgumentError, TypeError
        invalid(path)
      end

      def date(value, path)
        invalid(path) unless value.is_a?(String) || value.is_a?(Date)
        invalid(path) if value.is_a?(String) && !value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        value.is_a?(String) ? Date.iso8601(value) : value.to_date
      rescue ArgumentError, TypeError
        invalid(path)
      end

      def normalize_approval
        if @attributes.key?(:declaration) && @attributes.key?(:imported_approval)
          invalid(%w[declaration imported_approval])
        end
        key = @attributes.key?(:declaration) ? :declaration : (@attributes.key?(:imported_approval) ? :imported_approval : nil)
        return unless key
        allowed = %i[reviewer_name approved_at facts_checked] + (key == :declaration ? %i[declared_on declared_by declared_first_published_at] : %i[evidence confirmed_by])
        value = nested(@attributes[key], allowed, key.to_s)
        unless value[:reviewer_name].is_a?(String) && value[:reviewer_name].present? && [ true, false ].include?(value[:facts_checked])
          raise Error::ApprovalIncomplete
        end
        invalid("#{key}.approved_at") unless value[:approved_at]
        value[:approved_at] = timestamp(value[:approved_at], "#{key}.approved_at")
        if key == :declaration
          required_text(value, :declared_by, "declaration.declared_by")
          value[:declared_on] = date(value[:declared_on], "declaration.declared_on")
          @declared_first = timestamp(value.delete(:declared_first_published_at), "declaration.declared_first_published_at")
          invalid("declaration.declared_first_published_at") if @attributes[:first_published_at] && @declared_first
        else
          required_text(value, :evidence, "imported_approval.evidence")
          required_text(value, :confirmed_by, "imported_approval.confirmed_by")
        end
        @approval = value.merge(kind: key == :declaration ? "declared" : "imported")
      end

      def normalize_baseline
        provenance = @attributes.fetch(:provenance, "unknown").to_s
        invalid("provenance") unless %w[ai_assisted human_written unknown].include?(provenance)
        evidence = @attributes[:provenance_evidence]
        if evidence.blank? && @approval && @approval[:kind] == "declared"
          evidence = "Declared by #{@approval[:declared_by]} on #{@approval[:declared_on].iso8601}"
        end
        invalid("provenance_evidence") if provenance != "unknown" && evidence.blank?
        @baseline = @attributes.slice(:source_system, :source_id, :source_body_sha256).merge(
          source_body_sha256: @attributes[:source_body_sha256], provenance: provenance,
          provenance_evidence: evidence, declared_first_published_at: @declared_first)
        %i[first_published last_modified].each do |name|
          time = timestamp(@attributes[:"#{name}_at"], "#{name}_at")
          evidence = @attributes[:"#{name}_evidence"].presence
          @baseline[:"#{name}_at"] = evidence ? time : nil
          @baseline[:"#{name}_evidence"] = evidence
        end
      end

      def normalize_connections
        return unless @attributes.key?(:connections)
        value = nested(@attributes[:connections], %i[connections third_party_paid declared_by declared_on], "connections")
        required_text(value, :declared_by, "connections.declared_by")
        invalid("connections.third_party_paid") unless [ true, false ].include?(value[:third_party_paid])
        value[:declared_on] = value.key?(:declared_on) ? date(value[:declared_on], "connections.declared_on") : @now.to_date
        invalid("connections.connections") unless value[:connections].is_a?(Array)
        value[:connections] = value[:connections].map do |entry|
          normalized = nested(entry, %i[party relation], "connections.connections")
          %i[party relation].each { |field| required_text(normalized, field, "connections.connections.#{field}") }
          normalized.stringify_keys
        end
        @connections = value
      end
    end
  end
end
