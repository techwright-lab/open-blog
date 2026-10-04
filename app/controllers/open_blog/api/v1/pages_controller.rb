module OpenBlog
  module Api
    module V1
      class PagesController < ResourcesController
        def index
          require_scope!(:read)
          list(Page.all, :pages, ->(page) { PageSerializer.call(page, base_url: request.base_url) })
        end

        def show
          require_scope!(:read)
          input_fields!
          page = Page.find_by!(kind: params[:kind])
          render json: PageSerializer.call(page, base_url: request.base_url)
        end

        def update
          require_scope!(:write)
          input = page_attributes
          now = Time.current
          attempts = 0
          begin
            page, created = Page.transaction(requires_new: true) do
              current = Page.lock.find_by(kind: params[:kind]) || Page.new(kind: params[:kind])
              require_scope!(:publish) if current.status == "published" || input[:status] == "published"
              created = current.new_record?
              current.assign_attributes(input)
              current.approved_on = now.to_date if input[:approved_by].present? && !input.key?(:approved_on)
              current.save!
              [ current, created ]
            end
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
            # A concurrent first write can commit between the two uniqueness checks, so only the slug reports taken.
            collision = error.is_a?(ActiveRecord::RecordNotUnique) || (error.record.new_record? &&
              %i[kind slug].any? { |field| error.record.errors.of_kind?(field, :taken) })
            attempts += 1
            retry if collision && attempts == 1
            raise
          end
          render json: PageSerializer.call(page, base_url: request.base_url), status: created ? :created : :ok
        end

        private

        def page_attributes
          input = input_fields!(*ApiFields::SITE_PAGE)
          %i[title body slug].each do |field|
            invalid!(field) if input.key?(field) && !input[field].is_a?(String)
          end
          invalid!(:approved_by) if input.key?(:approved_by) && !input[:approved_by].nil? && !input[:approved_by].is_a?(String)
          invalid!(:status) if input.key?(:status) && !%w[draft published].include?(input[:status])
          if input.key?(:approved_on) && !input[:approved_on].nil?
            value = input[:approved_on]
            invalid!(:approved_on) unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
            begin
              input[:approved_on] = Date.iso8601(value)
            rescue Date::Error
              invalid!(:approved_on)
            end
          end
          input[:body_markdown] = input.delete(:body) if input.key?(:body)
          input
        end
      end
    end
  end
end
