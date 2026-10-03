pin "application"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from OpenBlog::Engine.root.join("app/assets/javascripts/open_blog/controllers"), under: "controllers/open_blog", to: "open_blog/controllers"
