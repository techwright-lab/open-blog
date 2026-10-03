module OpenBlog
  class Search
    def self.call(query, scope: Post.listed, limit: nil)
      return scope.none unless query.is_a?(String)
      query = query.strip
      return scope.none unless (2..100).cover?(query.length)

      relation = if Post.connection.adapter_name == "PostgreSQL"
        vector = "to_tsvector('simple', open_blog_posts.search_text)"
        expression = Post.sanitize_sql_array([ "websearch_to_tsquery('simple', ?)", query ])
        scope.where("#{vector} @@ #{expression}").reorder(Arel.sql("ts_rank(#{vector}, #{expression}) DESC"))
      else
        query.split.reduce(scope) do |matches, word|
          matches.where("LOWER(open_blog_posts.search_text) LIKE ? ESCAPE '\\'", "%#{Post.sanitize_sql_like(word.downcase)}%")
        end.reorder(nil)
      end
      relation = relation.order(created_at: :desc, id: :desc)
      limit ? relation.limit(limit) : relation
    end
  end
end
