OpenBlog::Engine.routes.draw do
  match "/mcp", to: "mcp#create", via: [ :post, :get, :delete ]
  get "/preview/:token", to: "previews#show", as: :preview
  get "/policies/:slug", to: "pages#show", as: :policy_page, format: false
  namespace :api do
    namespace :v1 do
      patch "posts/:id", to: "posts#update"
      resources :posts, only: [ :index, :show, :create, :destroy ] do
        post :publish, on: :member
        post :unpublish, on: :member
        resources :approvals, only: :create
        resources :connections, only: :create
        resource :views, only: :show, controller: "views"
        resource :preview, only: :show, controller: "previews"
        resource :records, only: :show, controller: "records"
        resource :findings, only: :show, controller: "findings"
      end
      resources :images, only: :create
      %i[categories authors series].each do |resource|
        resources resource, only: [ :index, :create ]
        patch "#{resource}/:id", to: "#{resource}#update"
      end
      resources :tags, only: :index
      resources :redirects, only: [ :index, :create, :destroy ]
      resources :adoptions, only: :create
      resources :faq_extractions, only: :create
      get "pages", to: "pages#index"
      get "pages/:kind", to: "pages#show"
      put "pages/:kind", to: "pages#update"
      get "views/top", to: "views#top"
      get "report", to: "report#show"
      get "doctor", to: "doctor#show"
    end
  end
  root "posts#index"
  get "/search", to: "search#show", as: :search
  get "/#{OpenBlog.config.route_segments.fetch(:series)}/:slug", to: "series#show", as: :series
  get "/feed.json", to: "feeds#show", as: :feed_json, format: false, defaults: { format: :json }
  get "/feed.xml", to: "feeds#show", as: :feed, format: false, defaults: { format: :xml }
  get "/sitemap.xml", to: "sitemaps#show", as: :sitemap, format: false, defaults: { format: :xml }
  get "/media/:sha256/:filename", to: "media#show", as: :media, format: false, constraints: { sha256: /[0-9a-f]{64}/, filename: /[^\/]+/ }
  get "/#{OpenBlog.config.route_segments.fetch(:category)}/:slug/feed.json", to: "feeds#show", as: :category_feed_json, format: false, defaults: { format: :json }
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
