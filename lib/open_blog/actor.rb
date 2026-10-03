module OpenBlog
  Actor = Data.define(:name, :scopes, :id) do
    def initialize(name:, scopes: %w[read write publish], id: nil)
      super(name: name.to_s, scopes: Array(scopes).map(&:to_s).freeze, id: id || name.to_s)
    end
  end
end
