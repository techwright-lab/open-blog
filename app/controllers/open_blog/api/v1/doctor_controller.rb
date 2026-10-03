module OpenBlog
  module Api
    module V1
      class DoctorController < BaseController
        def show
          require_scope!(:read)
          input_fields!
          render json: DoctorSerializer.call(Doctor.run)
        end
      end
    end
  end
end
