module OpenBlog
  module Api
    module V1
      class FindingsController < BaseController
        def show
          require_scope!(:read)
          input_fields!
          render json: FindingsSerializer.call(Findings.for(find_post!))
        end
      end
    end
  end
end
