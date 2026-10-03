module OpenBlog
  module DatesHelper
    def open_blog_dates(post)
      published = ReaderDates.published_at(post)
      modified = ReaderDates.modified_at(post)
      dates = []
      dates << open_blog_date(published, :published) if published
      dates << open_blog_date(modified, :updated) if modified && (!published || modified > published)
      safe_join(dates, " ")
    end

    def open_blog_date(time, label)
      tag.span(class: "ob-date ob-date--#{label}") do
        safe_join([ tag.span(open_blog_translate("dates.#{label}")), tag.time(I18n.l(time.to_date, format: :long, locale: OpenBlog.config.locale), datetime: time.iso8601) ], " ")
      end
    end
  end
end
