module OpenBlog
  module Api
    module V1
      class PreviewsController < BaseController
        def show
          require_scope!(:read)
          input_fields!
          render json: PreviewSerializer.call(find_post!, base_url: request.base_url)
        end
      end
    end
  end
end
