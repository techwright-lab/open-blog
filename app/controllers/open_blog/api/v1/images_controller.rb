module OpenBlog
  module Api
    module V1
      class ImagesController < BaseController
        def create
          require_scope!(:write)
          input = input_fields!(*ApiFields::IMAGE)
          raise Error::ImageNotPermitted unless input.size == 1
          image = if input.key?(:url)
            Image.from_url(input[:url], uploaded_by: actor.name)
          else
            file = input[:file]
            raise Error::ImageNotPermitted unless file.is_a?(ActionDispatch::Http::UploadedFile)
            Image.from_upload(file.tempfile, filename: file.original_filename,
              content_type: file.content_type, uploaded_by: actor.name)
          end
          render json: ImageSerializer.call(image), status: :created
        end
      end
    end
  end
end
