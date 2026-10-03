module OpenBlog
  module Api
    module V1
      class CategoriesController < ResourcesController
        def index
          require_scope!(:read)
          list(Category.all, :categories, CategorySerializer)
        end

        def create
          require_scope!(:write)
          render json: CategorySerializer.call(Category.create!(attributes)), status: :created
        end

        def update
          require_scope!(:write)
          record = Category.find(params[:id])
          record.update!(attributes)
          render json: CategorySerializer.call(record)
        end

        private

        def attributes
          input = input_fields!(:name, :slug, :description, :position)
          text_fields!(input, :name, :slug, :description)
          invalid!(:position) if input.key?(:position) && (!input[:position].is_a?(Integer) || !(-2_147_483_648..2_147_483_647).cover?(input[:position]))
          input
        end
      end
    end
  end
end
