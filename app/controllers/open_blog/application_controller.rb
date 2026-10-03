module OpenBlog
  class ApplicationController < OpenBlog.config.parent_controller.constantize
    include ReaderController
  end
end
