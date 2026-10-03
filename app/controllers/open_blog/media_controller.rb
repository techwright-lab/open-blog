module OpenBlog
  class MediaController < ApplicationController
    include ActiveStorage::SetCurrent
    rescue_from ActiveStorage::FileNotFoundError, with: :render_not_found

    def show
      image = Image.find_by!(sha256: params[:sha256])
      raise NotFound unless image.file.attached?
      if OpenBlog.config.image_delivery == :proxy
        expires_in 365.days, public: true, immutable: true
        send_data image.file.download, type: image.content_type, filename: image.filename, disposition: "inline"
      else
        lifetime = [ ActiveStorage.service_urls_expire_in.to_i, 365.days.to_i ].min
        expires_in lifetime, public: true
        redirect_to image.file.blob.url(expires_in: lifetime, disposition: "inline"), allow_other_host: true
      end
    end
  end
end
