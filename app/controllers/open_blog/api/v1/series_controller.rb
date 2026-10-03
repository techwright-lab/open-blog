module OpenBlog
  module Api
    module V1
      class SeriesController < ResourcesController
        def index
          require_scope!(:read)
          list(Series.all, :series, SeriesSerializer)
        end

        def create
          require_scope!(:write)
          render json: SeriesSerializer.call(Series.create!(attributes)), status: :created
        end

        def update
          require_scope!(:write)
          record = Series.find(params[:id])
          record.update!(attributes)
          render json: SeriesSerializer.call(record)
        end

        private

        def attributes
          input = input_fields!(*ApiFields::SERIES)
          text_fields!(input, :name, :slug, :description)
          input
        end
      end
    end
  end
end
