module OpenBlog
  module ApiTokens
    IDENTITY = /\A[a-z0-9_]+:\S{1,200}\z/

    Grant = Data.define(:manage_own, :manage_all, :scopes) do
      def initialize(manage_own:, manage_all:, scopes:)
        super(manage_own:, manage_all:, scopes: scopes.map(&:to_s).freeze)
      end
    end
  end
end
