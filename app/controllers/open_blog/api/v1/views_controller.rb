module OpenBlog
  module Api
    module V1
      class ViewsController < BaseController
        def show
          require_scope!(:read)
          input = input_fields!(*ApiFields::VIEWS)
          render json: PageViews.for(find_post!, **input)
        end

        def top
          require_scope!(:read)
          input = input_fields!(*ApiFields::TOP_VIEWS)
          render json: PageViews.top(**input, base_url: request.base_url)
        end
      end
    end
  end
end
