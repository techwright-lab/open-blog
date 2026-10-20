module OpenBlog
  class MediaController < ApplicationController
    include ActiveStorage::SetCurrent
    rescue_from ActiveStorage::FileNotFoundError, with: :render_not_found

    def show
      image = attached_image
      deliver(image.file, content_type: image.content_type, filename: image.filename)
    end

    def variant
      image = attached_image
      representation = image.file.variant(Image::VARIANTS.fetch(params[:variant])).processed
      deliver(representation, content_type: representation.content_type, filename: image.filename)
    end

    private

    def attached_image
      image = Image.find_by!(sha256: params[:sha256])
      raise NotFound unless image.file.attached?
      image
    end

    def deliver(file, content_type:, filename:)
      if OpenBlog.config.image_delivery == :proxy
        bytes = file.download
        expires_in 365.days, public: true, immutable: true
        send_data bytes, type: content_type, filename: filename, disposition: "inline"
      else
        lifetime = [ ActiveStorage.service_urls_expire_in.to_i, 365.days.to_i ].min
        expires_in lifetime, public: true
        redirect_to file.url(expires_in: lifetime, disposition: "inline"), allow_other_host: true
      end
    end
  end
end
