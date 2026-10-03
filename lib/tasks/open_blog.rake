namespace :open_blog do
  desc "Set up authentication during installation without replacing existing tokens"
  task install_token: :environment do
    if OpenBlog.config.authenticate
      puts "API token: using host authentication."
    elsif OpenBlog::ApiToken.exists?
      puts "API token: existing token kept; use open_blog:token to issue another if needed."
    else
      _record, secret = OpenBlog::ApiToken.generate(name: "Blog publisher")
      puts "API token: #{secret}"
      puts "Save this secret now; it will not be shown again."
    end
  end

  desc "Issue an API token and print its secret once"
  task token: :environment do
    name = ENV.fetch("NAME") { abort "Set NAME to identify this token's actor." }
    scopes = ENV.key?("SCOPES") ? ENV.fetch("SCOPES").split(",").map(&:strip) : OpenBlog::ApiToken::SCOPES
    expires_at = Time.iso8601(ENV.fetch("EXPIRES_AT")) if ENV["EXPIRES_AT"].present?
    _record, secret = OpenBlog::ApiToken.generate(name: name, scopes: scopes, expires_at: expires_at)
    puts secret
  end

  desc "Check the blog installation and report remaining setup"
  task doctor: :environment do
    checks = OpenBlog::Doctor.run
    checks.each { |check| puts "#{check[:status]}: #{check[:name]} — #{check[:message]}" }
    exit 1 if checks.any? { |check| check[:status].to_s == "error" }
  end

  desc "Create the sample article if it does not already exist"
  task sample: :environment do
    puts "Sample article: #{OpenBlog::Sample.call.path}"
  end

  desc "Generate scoped syntax colors for the configured light and dark theme"
  task :syntax_css, [ :path ] => :environment do |_task, arguments|
    puts "Wrote #{OpenBlog::SyntaxCss.write(path: arguments[:path])}"
  end
  desc "Build the packaged stylesheet and token-only theme override"
  task build_css: :environment do
    options = ENV["OUT"].present? ? { path: ENV["OUT"] } : {}
    puts "Wrote #{OpenBlog::BuildCss.write(**options)}"
  end
end

namespace :open_blog do
  desc "Publish scheduled posts that are due"
  task publish_due: :environment do
    OpenBlog::Post.where(status: "scheduled").where("publish_at <= ?", Time.current).find_each do |post|
      OpenBlog::PublishScheduledPostJob.perform_now(post.id)
    end
  end
end

namespace :open_blog do
  desc "Delete daily view totals older than the configured retention period"
  task prune_page_views: :environment do
    puts "Pruned #{OpenBlog::PageViews.prune!} daily view totals"
  end
end

namespace :open_blog do
  desc "Inspect public pages and publishing records"
  task report: :environment do
    puts OpenBlog::SurfaceReport.run(scope: ENV.fetch("SCOPE", "site"), post: ENV["POST"],
      page: ENV.fetch("PAGE", "1"), reach: ENV.fetch("REACH", "false")).to_text
  rescue OpenBlog::Error => error
    abort "#{error.code}: #{error.details.join(', ')}"
  end
end
