ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: 1) if ENV["DB"] == "sqlite"
  self.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
end
