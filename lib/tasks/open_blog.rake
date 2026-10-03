namespace :open_blog do
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
