class ApplicationController < ActionController::Base
end unless defined?(ApplicationController)

ActionCable.server.config.cable ||= { "adapter" => "test" }

require "open_blog/admin_suite"
OpenBlog::AdminSuite.install!
