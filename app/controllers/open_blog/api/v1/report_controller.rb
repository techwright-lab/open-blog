module OpenBlog
  module Api
    module V1
      class ReportController < BaseController
        def show
          require_scope!(:read)
          input = input_fields!(*ApiFields::REPORT, :format)
          format = input.delete(:format) || params[:format]
          raise Error::ValidationFailed.new(details: [ "format" ]) unless format.nil? || %w[json text].include?(format)
          report = SurfaceReport.run(**input)
          if format == "text" || (format.nil? && request.accepts.first == Mime[:text])
            render plain: report.to_text
          else
            render json: report.to_h
          end
        end
      end
    end
  end
end
