module OpenBlog
  class ErrorSerializer
    def self.call(error)
      { error: { code: error.code, message: error.message, details: error.details } }
    end
  end
end
