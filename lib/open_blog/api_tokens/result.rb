module OpenBlog
  module ApiTokens
    Result = Data.define(:token, :tokens, :secret, :error, :details) do
      def initialize(token: nil, tokens: [], secret: nil, error: nil, details: [])
        super
      end

      def success?
        error.nil?
      end
    end
  end
end
