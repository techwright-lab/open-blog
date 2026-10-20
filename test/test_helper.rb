ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: 1) if ENV["DB"] == "sqlite"
  self.fixture_paths = [ File.expand_path("fixtures", __dir__) ]

  def skip_unless_rich_text_embeds
    return if ActionText::RichText.type_for_attribute("id").type == ActiveStorage::Attachment.type_for_attribute("record_id").type
    skip "Host Action Text IDs cannot be Active Storage attachment records"
  end
end
