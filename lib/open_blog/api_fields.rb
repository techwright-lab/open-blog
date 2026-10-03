module OpenBlog
  module ApiFields
    POST_WRITE = (PostAttributes::CONTENT_FIELDS + PostAttributes::RECORD_FIELDS).freeze
    POST_LIST = %i[status category tag author series q page per_page].freeze
    POST_NESTED = {
      author: %i[name type url], approval: %i[name facts_checked revision_identifier],
      cover_image: %i[image_id signed_id url], social_image: %i[image_id signed_id url],
      connections: %i[connections third_party_paid declared_by declared_on], faq: %i[question answer]
    }.freeze
    APPROVAL = %i[revision_identifier name facts_checked].freeze
    CONNECTION = %i[connections third_party_paid declared_by declared_on].freeze
    CATEGORY = %i[name slug description position].freeze
    AUTHOR = %i[name slug type bio url profile_urls host_reference avatar].freeze
    SERIES = %i[name slug description].freeze
    REDIRECT = %i[old_path new_path occurred_on post_id].freeze
    ADOPTION = (Adopt::Contract::CONTENT_FIELDS + Adopt::Contract::EXTRA_FIELDS).freeze
    EXTRACTION = %i[body standalone_questions].freeze
    PAGE = %i[page per_page].freeze
    IMAGE = %i[file url].freeze
    REMOVE = %i[redirect_to].freeze

    def self.validate_post_images!(attributes)
      %i[cover_image social_image].each do |field|
        value = attributes[field]
        next if value.nil?
        raise Error::ImageNotPermitted unless value.is_a?(Hash) && value.size == 1
        if value.key?(:image_id)
          raise Error::ImageNotPermitted unless value[:image_id].is_a?(Integer) && value[:image_id].positive?
        else
          key = value.keys.first
          raise Error::ImageNotPermitted unless %i[signed_id url].include?(key) && value[key].is_a?(String)
        end
      end
    end
  end
end
