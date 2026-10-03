module OpenBlog
  module Api
    module V1
      class RecordsController < BaseController
        def show
          require_scope!(:read)
          input_fields!
          render json: RecordsSerializer.call(find_post!)
        end
      end
    end
  end
end
