module OpenBlog
  module Api
    module V1
      class RedirectsController < ResourcesController
        def index
          require_scope!(:read)
          list(Redirect.all, :redirects, RedirectSerializer)
        end

        def create
          require_scope!(:publish)
          input = input_fields!(*ApiFields::REDIRECT)
          text_fields!(input, :old_path, :new_path, :occurred_on)
          old = input[:old_path]
          invalid!(:old_path) unless old.is_a?(String) && old.start_with?("/") && !old.start_with?("//") && !old.match?(/[\s?#]/)
          invalid!(:post_id) if input.key?(:post_id) && !input[:post_id].nil? && !input[:post_id].is_a?(Integer)
          date = input.key?(:occurred_on) ? parse_date(input[:occurred_on]) : Date.current
          record = Redirect.transaction do
            Post.lock.find(input[:post_id]) if input[:post_id]
            RedirectTarget.synchronize do
              prefix = "#{OpenBlog.mount_path.chomp('/')}/"
              slug = old.delete_prefix(prefix)
              raise Error::SlugReserved if old.start_with?(prefix) && Post.exists?(slug: slug)
              target = RedirectTarget.call(input[:new_path], from: old)
              row = Redirect.create!(old_path: old, new_path: target, occurred_on: date, source: "manual", post_id: input[:post_id])
              Redirect.where(new_path: old).where.not(id: row.id).find_each { |incoming| incoming.update!(new_path: target) }
              row
            end
          end
          render json: RedirectSerializer.call(record), status: :created
        end

        def destroy
          require_scope!(:publish)
          input_fields!
          RedirectTarget.synchronize { Redirect.find(params[:id]).destroy! }
          head :no_content
        end

        private

        def parse_date(value)
          invalid!(:occurred_on) unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          Date.iso8601(value)
        rescue Date::Error
          invalid!(:occurred_on)
        end
      end
    end
  end
end
