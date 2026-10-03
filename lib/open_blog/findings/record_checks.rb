require "uri"
require "commonmarker"

module OpenBlog
  module Findings
    module RecordChecks
      class << self
        def build
          [
            check(:description_absent, "T8", "Add a description for readers and search results.", "description") { |post, _| description(post).blank? },
            check(:title_duplicate, "T7", "Another published post uses this title.", "title") { |post, _| other_posts(post).exists?(title: post.title) },
            check(:description_duplicate, "T8", "Another published post uses this search description.", "search_description") { |post, _| duplicate_description?(post) },
            check(:category_absent, "T21", "Choose a category for this post.", "category") { |post, _| primary_categories? && post.category.nil? },
            check(:category_description_absent, "T21", "Add an introduction to this category.", "category.description") { |post, _| primary_categories? && post.category && post.category.description.blank? },
            check(:faq_question_duplicate, nil, "An FAQ question appears more than once.", ->(_, _, index) { "faq[#{index}].question" }) { |post, _| duplicate_question(post) },
            check(:faq_markup_in_answer, "E19", "FAQ answers display plain text; remove formatting markup.", ->(_, _, index) { "faq[#{index}].answer" }) { |post, _| markup_answer(post) },
            check(:faq_in_body, nil, "Move this FAQ section into the post's FAQ entries to avoid duplicate content.", "body") { |post, _| post.markdown? && FaqExtraction.contains_faq_heading?(post.body_markdown) },
            check(:author_default_used, "E1", "This post uses the configured default author.", "author") { |_, context| context[:author_default_used] },
            check(:provenance_unknown, "E18", "Specify whether AI contributed to this post.", "provenance") { |post, _| post.provenance_unknown? },
            check(:approval_absent, "E18", "This revision has no approval confirming its facts.", "approval") { |post, _| approval_absent?(post) },
            check(:approval_incomplete, "E18", "The supplied approval says its facts were not checked.", "approval.facts_checked") { |_, context| context[:approval_incomplete] },
            check(:connections_not_declared, "E21, E22", "Record any relevant relationships, including an explicit declaration of none.", "connections") { |post, _| !post.connection_declarations.exists? },
            check(:responsible_party_absent, "E4", "Configure a page naming the person or organization responsible for the blog.") { |_, _| OpenBlog.config.policy_urls[:responsible_party].blank? },
            check(:canonical_off_site, "T5", "This canonical URL points outside the blog's configured origin.", "canonical_url") { |post, _| canonical_off_site?(post) },
            check(:slug_changed, "T4", "The previous public URL now redirects to this post.", "slug") { |_, context| context[:slug_changed] },
            check(:social_image_absent, "T17", "Choose a social image, cover image, or blog default image.", "social_image") { |post, _| post.cover_image_id.nil? && post.social_image_id.nil? && OpenBlog.config.default_social_image_url.blank? }
          ]
        end

        private

        def check(code, rule, message, location = nil, &predicate)
          Check.new(code: code, rule: rule, message: message, location: location, &predicate)
        end

        def other_posts(post)
          Post.listed.where.not(id: post.id)
        end

        def description(post)
          post.search_description.presence || post.description
        end

        def duplicate_description?(post)
          value = description(post)
          value.present? && other_posts(post).pluck(:description, :search_description).any? do |editorial, search|
            (search.presence || editorial) == value
          end
        end

        def primary_categories?
          OpenBlog.config.primary_list_type == :categories
        end

        def duplicate_question(post)
          seen = []
          post.faq_list.each_with_index do |entry, index|
            question = entry[:question].to_s.unicode_normalize(:nfc).strip.downcase
            return index if seen.include?(question)
            seen << question
          end
          nil
        end

        def markup_answer(post)
          post.faq_list.index { |entry| markup?(Commonmarker.parse(entry[:answer].to_s), entry[:answer].to_s) }
        end

        def markup?(node, source)
          if node.type == :link
            return true if source.match?(/[\[<]/)
          elsif !%i[document paragraph text softbreak linebreak].include?(node.type)
            return true
          end
          node.each.any? { |child| markup?(child, source) }
        end

        def approval_absent?(post)
          return false if post.provenance_human_written? || (!post.published? && !post.scheduled?)
          identifier = post.published? ? post.public_revision&.identifier : post.current_revision_identifier
          !identifier || !post.approvals.joins(:revision).exists?(facts_checked: true, open_blog_revisions: { identifier: identifier })
        end

        def canonical_off_site?(post)
          return false if post.canonical_url.blank? || OpenBlog.config.public_base_url.blank?
          canonical, base = [ post.canonical_url, OpenBlog.config.public_base_url ].map { |value| URI.parse(value) }
          [ canonical.scheme, canonical.host&.downcase, canonical.port ] != [ base.scheme, base.host&.downcase, base.port ]
        rescue URI::InvalidURIError
          false
        end
      end
    end
  end
end
