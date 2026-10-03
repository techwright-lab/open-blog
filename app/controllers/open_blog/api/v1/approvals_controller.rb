module OpenBlog
  module Api
    module V1
      class ApprovalsController < BaseController
        def create
          require_scope!(:publish)
          input = input_fields!(:revision_identifier, :name, :facts_checked)
          result = Approve.call(find_post!, revision_identifier: input[:revision_identifier],
            name: input[:name], facts_checked: input[:facts_checked], actor: actor.name)
          render_result(result, status: :ok)
        end
      end
    end
  end
end
