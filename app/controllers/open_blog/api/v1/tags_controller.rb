module OpenBlog
  module Api
    module V1
      class TagsController < ResourcesController
        def index
          require_scope!(:read)
          list(Tag.all, :tags, TagSerializer)
        end
      end
    end
  end
end
