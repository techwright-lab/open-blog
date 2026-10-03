module OpenBlog
  module Api
    module V1
      class AuthorsController < ResourcesController
        def index
          require_scope!(:read)
          list(Author.all, :authors, AuthorSerializer)
        end

        def create
          require_scope!(:write)
          save_author(Author.new, status: :created)
        end

        def update
          require_scope!(:write)
          save_author(Author.find(params[:id]), status: :ok)
        end

        private

        def save_author(record, status:)
          input = input_fields!(*ApiFields::AUTHOR)
          text_fields!(input, :name, :slug, :type, :bio, :url, :host_reference)
          if input.key?(:profile_urls)
            invalid!(:profile_urls) unless input[:profile_urls].is_a?(Array) && input[:profile_urls].all? { |url| url.is_a?(String) }
          end
          avatar_sent = input.key?(:avatar)
          avatar = input.delete(:avatar)
          input[:author_type] = input.delete(:type) if input.key?(:type)
          record.assign_attributes(input)
          raise ActiveRecord::RecordInvalid, record unless record.valid?
          prepared, image = prepare_avatar(avatar) if avatar_sent && avatar
          Author.transaction do
            record.reload.lock! if record.persisted?
            record.assign_attributes(input)
            image = prepared.persist(uploaded_by: actor.name) if prepared
            if avatar_sent
              invalid!(:avatar) if image && !image.file.attached?
              record.avatar = image&.file&.blob
            end
            record.save!
          end
          render json: AuthorSerializer.call(record), status: status
        end

        def prepare_avatar(input)
          invalid!(:avatar) unless input.is_a?(Hash)
          unknown = input.keys - %i[image_id signed_id url]
          raise Error::UnknownField.new(details: unknown.map { |field| "avatar.#{field}" }) if unknown.any?
          invalid!(:avatar) unless input.size == 1
          if input.key?(:image_id)
            invalid!(:avatar) unless input[:image_id].is_a?(Integer)
            [ nil, Image.find(input[:image_id]) ]
          else
            [ ImageImport.prepare(input), nil ]
          end
        end
      end
    end
  end
end
