require "digest"

module OpenBlog
  class PostAttributes
    CONTENT_FIELDS = %i[title description search_title search_description body body_format author cover_image cover_alt social_image faq category tags series series_position featured canonical_url slug external_id].freeze
    RECORD_FIELDS = %i[provenance provenance_evidence made_by_ai approval change change_description note connections publish_at].freeze
    TEXT_FIELDS = %i[title description search_title search_description body cover_alt canonical_url slug external_id provenance_evidence].freeze

    def self.normalize(attributes)
      unless attributes.is_a?(Hash) && attributes.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
        raise Error::ValidationFailed.new(details: [ "attributes" ])
      end
      normalized = attributes.symbolize_keys
      unknown = normalized.keys - CONTENT_FIELDS - RECORD_FIELDS
      raise Error::UnknownField.new(details: unknown.map(&:to_s)) if unknown.any?
      normalized
    end

    def self.assign(post, attributes, actor:, now:)
      new(post, normalize(attributes), actor: actor, now: now).assign
    rescue ActiveRecord::RecordNotFound
      raise Error::NotFound
    rescue ActiveRecord::RecordInvalid => error
      raise Error::ValidationFailed.new(details: error.record.errors.attribute_names.map(&:to_s))
    end

    def initialize(post, attributes, actor:, now:)
      @post, @attributes, @actor, @now = post, attributes, actor, now
    end

    def assign
      validate_types
      assign_scalars
      assign_author if @attributes.key?(:author) || @post.author.nil?
      %i[category series].each do |field|
        @post.public_send("#{field}=", taxonomy(OpenBlog.const_get(field.to_s.classify), @attributes[field])) if @attributes.key?(field)
      end
      assign_faq if @attributes.key?(:faq)
      assign_tags if @attributes.key?(:tags)
      %i[cover_image social_image].each do |field|
        @post.public_send("#{field}=", image(@attributes[field])) if @attributes.key?(field)
      end
      assign_provenance
      PostIdentity.resolve({ slug: @post.slug }, post: @post)
      @post
    end

    private

    def invalid(field)
      raise Error::ValidationFailed.new(details: [ field.to_s ])
    end

    def validate_types
      TEXT_FIELDS.each { |field| invalid(field) if @attributes.key?(field) && !@attributes[field].nil? && !@attributes[field].is_a?(String) }
      invalid(:featured) if @attributes.key?(:featured) && ![ true, false ].include?(@attributes[:featured])
      if @attributes.key?(:series_position) && !@attributes[:series_position].nil?
        invalid(:series_position) unless @attributes[:series_position].is_a?(Integer) && @attributes[:series_position].positive?
      end
      %i[category series].each do |field|
        invalid(field) if @attributes.key?(field) && !@attributes[field].nil? && !@attributes[field].is_a?(String)
      end
      if @attributes.key?(:body_format)
        format = @attributes[:body_format]
        unless (format.is_a?(String) || format.is_a?(Symbol)) && OpenBlog.config.body_formats.map(&:to_s).include?(format.to_s)
          raise Error::BodyFormatNotPermitted
        end
      end
      if @attributes.key?(:provenance) && !%w[ai_assisted human_written unknown].include?(@attributes[:provenance].to_s)
        invalid(:provenance)
      end
      if @attributes.key?(:tags)
        invalid(:tags) unless @attributes[:tags].is_a?(Array) && @attributes[:tags].all? { |tag| tag.is_a?(String) && tag.present? }
      end
      if @attributes.key?(:faq)
        invalid(:faq) unless @attributes[:faq].is_a?(Array)
        @attributes[:faq].each do |entry|
          invalid(:faq) unless entry.is_a?(Hash)
          values = entry.stringify_keys
          invalid(:faq) unless values.keys.sort == %w[answer question] && values.values.all? { |value| value.is_a?(String) && value.present? }
        end
      end
    end

    def assign_scalars
      fields = TEXT_FIELDS - %i[body provenance_evidence]
      (fields + %i[featured series_position body_format]).each do |field|
        @post.public_send("#{field}=", @attributes[field]) if @attributes.key?(field)
      end
      %i[description search_title search_description cover_alt].each do |field|
        @post.public_send("#{field}=", "") if @post.public_send(field).nil?
      end
      @post.canonical_url = nil if @post.canonical_url.blank?
      if @post.slug.blank?
        @post.slug = @post.title.to_s.parameterize.presence || "post-#{Digest::SHA256.hexdigest(@post.title.to_s)[0, 12]}"
      end
      if @attributes.key?(:body)
        @post.public_send(@post.markdown? ? "body_markdown=" : "rich_body=", @attributes[:body])
      end
    end

    def assign_author
      input = @attributes.key?(:author) ? @attributes[:author] : OpenBlog.config.default_author
      author = case input
      when Author then input
      when Integer then Author.find(input)
      when String
        invalid(:author) if input.blank?
        if input.match?(/\A[1-9]\d*\z/)
          Author.find(input)
        else
          Author.find_by(slug: input) || Author.find_by(name: input) || Author.create!(name: input)
        end
      when Hash
        fields = input.symbolize_keys
        invalid(:author) unless (fields.keys - %i[name type url]).empty? && fields[:name].is_a?(String) && fields[:name].present?
        invalid(:author) if fields.key?(:type) && !%w[person organization].include?(fields[:type].to_s)
        invalid(:author) if fields.key?(:url) && !fields[:url].nil? && !fields[:url].is_a?(String)
        Author.find_by(name: fields[:name]) || Author.create!(name: fields[:name], author_type: fields.fetch(:type, :person).to_s, url: fields[:url])
      else invalid(:author)
      end
      @post.author = author
      @post.author_name = author.name
    end

    def taxonomy(model, value)
      return if value.blank?
      model.find_by(slug: value) || model.find_by(name: value) || model.create!(name: value)
    end

    def assign_faq
      existing = @post.faqs.to_a.sort_by(&:position)
      @attributes[:faq].each_with_index do |entry, index|
        record = existing[index] || @post.faqs.build(position: (existing.last&.position || 0) + index + 1)
        record.assign_attributes(entry.symbolize_keys)
      end
      existing.drop(@attributes[:faq].length).each(&:mark_for_destruction)
    end

    def assign_tags
      tags = @attributes[:tags].uniq(&:downcase).map do |name|
        Tag.where("LOWER(name) = ?", name.downcase).first || Tag.create!(name: name)
      end
      @post.taggings.each { |tagging| tagging.mark_for_destruction unless tags.any? { |tag| tag.id == tagging.tag_id } }
      existing = @post.taggings.reject(&:marked_for_destruction?).map(&:tag_id)
      tags.each { |tag| @post.taggings.build(tag: tag) unless existing.include?(tag.id) }
      @post.association(:tags).target = tags
      @post.association(:tags).loaded!
    end

    def image(input)
      return if input.nil?
      return input if input.is_a?(Image) && input.persisted?
      return Image.find(input) if input.is_a?(Integer)
      if input.is_a?(Hash) && input.keys.map(&:to_s) == [ "image_id" ]
        id = input[:image_id] || input["image_id"]
        return Image.find(id) if id.is_a?(Integer) || (id.is_a?(String) && id.match?(/\A[1-9]\d*\z/))
      end
      raise Error::ImageNotPermitted
    end

    def assign_provenance
      changed = @attributes.key?(:provenance) && @post.provenance != @attributes[:provenance].to_s
      @post.provenance = @attributes[:provenance] if @attributes.key?(:provenance)
      if @attributes.key?(:provenance_evidence)
        @post.provenance_evidence = @attributes[:provenance_evidence]
      elsif changed
        @post.provenance_evidence = "Stated by #{@actor} in the call of #{@now.iso8601}"
      end
    end
  end
end
