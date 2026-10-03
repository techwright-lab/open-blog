require_relative "test_helper"

if Gem.loaded_specs.key?("admin_suite")
  require_relative "support/admin_suite"

  class AdminSuiteAdapterTest < ActiveSupport::TestCase
    setup { OpenBlog::AdminSuite.install! }

    test "FAQ fields render existing records and one detached blank row without database writes" do
      post = OpenBlog::SaveDraft.call({ title: "FAQ editor", faq: [ { question: "When?", answer: "Before noon." } ] }, actor: "Editor").post
      view = ActionView::Base.empty
      form = ActionView::Helpers::FormBuilder.new("post", post, view, {})
      field = Struct.new(:readonly).new(false)
      writes = []
      observer = ->(*arguments) { sql = arguments.last[:sql]; writes << sql if sql.match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
      html = nil
      ActiveSupport::Notifications.subscribed(observer, "sql.active_record") do
        html = ::AdminSuite::UI::FieldRendererRegistry.render(:open_blog_faq, view: view, f: form, field: field, resource: post, field_class: "form-input")
      end
      document = Nokogiri::HTML.fragment(html)
      assert_equal 2, document.css("fieldset").length
      assert_equal "When?", document.at_css('input[name="post[faqs_attributes][0][question]"]')["value"]
      assert_equal "Before noon.", document.at_css('textarea[name="post[faqs_attributes][0][answer]"]').text.strip
      assert_equal "2", document.at_css('input[type="number"][name="post[faqs_attributes][1][position]"]')["value"]
      assert_equal post.faqs.first.id.to_s, document.at_css('input[name="post[faqs_attributes][0][id]"]')["value"]
      assert_equal 1, post.faqs.size
      assert_empty writes
    end

    test "parameter extension preserves ordinary fields and strictly scopes nested fields" do
      field = Struct.new(:name, :type).new(:faqs_attributes, :open_blog_faq)
      config = Struct.new(:form_config).new(Struct.new(:fields_list).new([ field ]))
      controller = Class.new do
        attr_accessor :params, :resource_class, :resource_config, :resource_name, :current_portal
        def resource_params
          params.require(resource_class.model_name.param_key).permit(:title)
        end
        prepend OpenBlog::AdminSuite::ResourceParameters
      end.new
      controller.resource_class = OpenBlog::Post
      controller.resource_config = config
      original = ActionController::Parameters.new(post: { title: "A changed title", faqs_attributes: {
        "0" => { id: 1, question: "When?", answer: "At dawn.", position: 1, _destroy: "0", post_id: 99, secret: "no" }
      } })
      controller.params = original
      result = controller.send(:resource_params)
      assert result.permitted?
      assert_equal "A changed title", result[:title]
      assert_equal %w[_destroy answer id position question], result[:faqs_attributes]["0"].keys.sort
      assert_same original, controller.params
      policy = ActionController::Parameters.action_on_unpermitted_parameters
      begin
        ActionController::Parameters.action_on_unpermitted_parameters = :raise
        strict = ActionController::Parameters.new(post: { title: "Strict fields", faqs_attributes: { "0" => { question: "What?", answer: "A path.", position: 1 } } })
        controller.params = strict
        assert controller.send(:resource_params).dig(:faqs_attributes, "0", :question)
        assert_same strict, controller.params
        strict[:post][:unexpected] = "refuse"
        assert_raises(ActionController::UnpermittedParameters) { controller.send(:resource_params) }
        assert_same strict, controller.params
      ensure
        ActionController::Parameters.action_on_unpermitted_parameters = policy
        controller.params = original
      end
      controller.resource_config = Struct.new(:form_config).new(Struct.new(:fields_list).new([]))
      refute controller.send(:resource_params).key?(:faqs_attributes)
    end

    test "installation is idempotent and native controller authorization is preserved" do
      2.times { OpenBlog::AdminSuite.install! }
      assert_equal 1, ::AdminSuite::ResourcesController.ancestors.count(OpenBlog::AdminSuite::ResourceParameters)
      callbacks = ::AdminSuite::ResourcesController._process_action_callbacks.map(&:filter)
      assert_includes callbacks, :authorize_admin_suite!
    end
  end
end
