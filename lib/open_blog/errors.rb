module OpenBlog
  class Error < StandardError
    attr_reader :code, :status, :details

    def initialize(message = nil, details: [])
      @code = self.class::CODE
      @status = self.class::STATUS
      @details = Array(details)
      super(message || self.class::MESSAGE)
    end

    {
      unauthenticated: [ 401, "An authenticated actor is required." ],
      scope_required: [ 403, "The actor lacks the required scope." ],
      not_found: [ 404, "The requested record was not found." ],
      identity_conflict: [ 409, "The external ID and slug identify different posts." ],
      slug_reserved: [ 409, "This slug belongs to a route or another post's redirect." ],
      post_is_public: [ 409, "This post is public. Update it through Publish." ],
      revision_mismatch: [ 409, "The revision identifier does not match the content being approved." ],
      already_changed_in_gem: [ 409, "This post has changed since its adoption." ],
      validation_failed: [ 422, "One or more fields are invalid." ],
      unknown_field: [ 422, "The request contains unsupported fields." ],
      change_type_required: [ 422, "This update changes the public revision. Send change: substantive, correction or maintenance." ],
      correction_note_required: [ 422, "A correction needs a note describing what changed." ],
      approval_required: [ 422, "This publication requires approval with facts checked." ],
      approval_incomplete: [ 422, "Approval requires a reviewer name and a boolean facts_checked value." ],
      refused_by_host: [ 422, "The host declined this publication." ],
      body_format_not_permitted: [ 422, "This body format is not enabled." ],
      slug_not_supported: [ 422, "The slug contains unsupported characters." ],
      image_not_permitted: [ 422, "The image input is not supported." ],
      rate_limited: [ 429, "The request limit has been reached. Try again later." ]
    }.each do |code, (status, message)|
      subclass = Class.new(self)
      subclass.const_set(:CODE, code)
      subclass.const_set(:STATUS, status)
      subclass.const_set(:MESSAGE, message.freeze)
      const_set(code.to_s.split("_").map(&:capitalize).join, subclass)
    end
  end
end
