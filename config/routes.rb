OpenBlog::Engine.routes.draw do
  root "posts#index"
  get "/feed.xml", to: "feeds#show", as: :feed, format: false, defaults: { format: :xml }
  get "/sitemap.xml", to: "sitemaps#show", as: :sitemap, format: false, defaults: { format: :xml }
  get "/media/:sha256/:filename", to: "media#show", as: :media, format: false, constraints: { sha256: /[0-9a-f]{64}/, filename: /[^\/]+/ }
  get "/#{OpenBlog.config.route_segments.fetch(:category)}/:slug/feed.xml", to: "feeds#show", as: :category_feed, format: false, defaults: { format: :xml }
  get "/#{OpenBlog.config.route_segments.fetch(:category)}/:slug", to: "categories#show", as: :category
  get "/#{OpenBlog.config.route_segments.fetch(:tag)}/:slug", to: "tags#show", as: :tag
  get "/#{OpenBlog.config.route_segments.fetch(:author)}/:slug", to: "authors#show", as: :author
  get "/:slug", to: "posts#show", as: :post, constraints: ->(request) {
    slug = request.path_parameters[:slug]
    slug.match?(/\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/) && !(OpenBlog::Post::RESERVED_SLUGS + OpenBlog.config.route_segments.values).include?(slug)
  }
  get "/*path", to: "errors#not_found"
end
