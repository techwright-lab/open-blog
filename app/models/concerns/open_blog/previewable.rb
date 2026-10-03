module OpenBlog
  module Previewable
    extend ActiveSupport::Concern
    TOKEN_LOCK = Mutex.new

    class_methods do
      def with_preview_tokens
        TOKEN_LOCK.synchronize do
          duration = OpenBlog.config.preview_duration
          unless token_definitions[:preview]&.expires_in == duration
            generates_token_for(:preview, expires_in: duration) { current_revision_identifier }
          end
          yield duration
        end
      end

      def find_by_preview_token(token)
        return unless token.is_a?(String)
        with_preview_tokens { find_by_token_for(:preview, token) }
      end
    end

    def previewable?
      persisted? && (draft? || scheduled?)
    end

    def preview_token
      preview_credentials.fetch(:token)
    end

    def preview_credentials
      raise Error::NotFound unless previewable?
      self.class.with_preview_tokens do |duration|
        { token: generate_token_for(:preview), expires_at: Time.current + duration }
      end
    end
  end
end
