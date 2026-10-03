require "admin_suite"
require "admin_suite/ui/field_renderer_registry"

module OpenBlog
  module AdminSuite
    RESOURCES = { "open_blog_posts" => "Post", "open_blog_categories" => "Category",
      "open_blog_authors" => "Author", "open_blog_pages" => "Page" }.freeze
    FAQ_FIELDS = %i[id question answer position _destroy].freeze

    module ResourceParameters
      private

      def resource_config
        name = RESOURCES[resource_name]
        return super unless current_portal.to_s == "open_blog" && name
        ensure_resources_loaded!
        definition = "::Admin::Resources::OpenBlog::#{name}Resource".safe_constantize
        return unless definition.is_a?(Class) && definition < ::Admin::Base::Resource
        definition if definition.model_class == "::OpenBlog::#{name}".constantize
      end

      def resource_params
        fields = resource_config&.form_config&.fields_list || []
        nested = resource_class == ::OpenBlog::Post && fields.any? do |field|
          field.respond_to?(:name) && field.name.to_sym == :faqs_attributes && field.type == :open_blog_faq
        end
        return super unless nested

        original = params
        key = resource_class.model_name.param_key
        faq = original.require(key).slice(:faqs_attributes).permit(faqs_attributes: FAQ_FIELDS)
        filtered = original.deep_dup
        filtered[key].delete(:faqs_attributes)
        self.params = filtered
        super.merge(faq)
      ensure
        self.params = original if original
      end
    end

    def self.install!
      return if @installed
      ::AdminSuite::UI::FieldRendererRegistry.register(:open_blog_faq) do |view, form, field, resource, field_class|
        render_faqs(view, form, field, resource, field_class)
      end
      Rails.application.reloader.to_prepare { install_controller! }
      install_controller!
      @installed = true
    end

    def self.install_controller!
      controller = ::AdminSuite::ResourcesController
      controller.prepend(ResourceParameters) unless controller.ancestors.include?(ResourceParameters)
    end

    def self.render_faqs(view, form, field, resource, field_class)
      entries = resource.faqs.to_a
      next_position = entries.filter_map(&:position).max.to_i + 1
      entries += [ ::OpenBlog::Faq.new(position: next_position) ] unless field.readonly
      form.fields_for(:faqs, entries, include_id: false) do |nested|
        view.tag.fieldset(class: "open-blog-faq-fields") do
          view.safe_join([
            view.tag.legend(nested.object.persisted? ? "FAQ #{nested.object.position}" : "Add a FAQ"),
            nested.hidden_field(:id), nested.label(:position), nested.number_field(:position, min: 1, class: field_class, readonly: field.readonly),
            nested.label(:question), nested.text_field(:question, class: field_class, readonly: field.readonly),
            nested.label(:answer), nested.text_area(:answer, class: field_class, rows: 4, readonly: field.readonly),
            nested.check_box(:_destroy, disabled: field.readonly), nested.label(:_destroy, "Remove this FAQ")
          ])
        end
      end
    end
  end
end
