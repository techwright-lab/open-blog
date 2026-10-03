namespace :open_blog do
  desc "Generate scoped syntax colors for the configured light and dark theme"
  task :syntax_css, [ :path ] => :environment do |_task, arguments|
    puts "Wrote #{OpenBlog::SyntaxCss.write(path: arguments[:path])}"
  end
  desc "Build the packaged stylesheet and token-only theme override"
  task build_css: :environment do
    puts "Wrote #{OpenBlog::BuildCss.write}"
  end
end
