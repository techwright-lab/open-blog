module OpenBlog
  module Api
    module V1
      class FaqExtractionsController < BaseController
        def create
          require_scope!(:read)
          input = input_fields!(:body, :standalone_questions)
          render json: ExtractionResultSerializer.call(FaqExtraction.call(body: input[:body], standalone_questions: input.fetch(:standalone_questions, [])))
        end
      end
    end
  end
end
