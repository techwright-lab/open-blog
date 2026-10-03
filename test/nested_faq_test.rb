require_relative "test_helper"

class NestedFaqTest < ActiveSupport::TestCase
  test "one native save edits adds and removes FAQs in a single public revision without claiming approval" do
    result = OpenBlog::Publish.call({ title: "A woodland route", body: "Follow the brook.", faq: [ { question: "When?", answer: "Morning." }, { question: "How far?", answer: "A mile." } ] }, actor: "Editor")
    post = result.post
    first, removed = post.faqs.to_a
    revisions, publications, approvals = post.revisions.count, post.publications.count, post.approvals.count
    post.update!(title: "A revised woodland route", faqs_attributes: {
      "0" => { id: first.id, question: "When to go?", answer: "Before noon.", position: 1 },
      "1" => { id: removed.id, _destroy: "1" },
      "2" => { question: "What to carry?", answer: "Water.", position: 3 },
      "3" => { question: "", answer: "", position: 4 }
    })
    assert_equal [ "When to go?", "What to carry?" ], post.reload.faq_list.pluck(:question)
    assert_equal revisions + 1, post.revisions.count
    assert_equal publications + 1, post.publications.count
    assert_equal approvals, post.approvals.count
    assert_equal "substantive", post.publications.order(:id).last.entry_type
    assert_nil post.publications.order(:id).last.released_by
    assert_nil post.public_revision.actor
    assert_equal post.faq_list.map(&:stringify_keys), JSON.parse(post.public_revision.payload).fetch("faq")
  end

  test "clearing an existing FAQ fails validation rather than silently keeping old content" do
    post = OpenBlog::SaveDraft.call({ title: "Existing FAQ", faq: [ { question: "When?", answer: "Morning." } ] }, actor: "Editor").post
    refute post.update(faqs_attributes: [ { id: post.faqs.first.id, question: "", answer: "" } ])
    assert_equal "When?", post.reload.faqs.first.question
  end

  test "duplicate requested positions roll back content while an unused position can reorder" do
    post = OpenBlog::Publish.call({ title: "FAQ positions", faq: [ { question: "First?", answer: "One." }, { question: "Second?", answer: "Two." } ] }, actor: "Editor").post
    first, second = post.faqs.to_a
    count = post.revisions.count
    refute post.update(title: "Should roll back", faqs_attributes: [ { id: first.id, position: second.position } ])
    assert_equal "FAQ positions", post.reload.title
    assert_equal count, post.revisions.count
    assert post.update(faqs_attributes: [ { id: first.id, position: 3 } ])
    assert_equal [ "Second?", "First?" ], post.reload.faq_list.pluck(:question)
    assert_equal count + 1, post.revisions.count
  end

  test "a partial new FAQ fails the entire save and another post FAQ cannot be stolen" do
    post = OpenBlog::SaveDraft.call({ title: "Pond route", body: "Keep to the bank." }, actor: "Editor").post
    refute post.update(title: "Unsaved replacement", faqs_attributes: [ { question: "When?", answer: "", position: 1 } ])
    assert_equal "Pond route", post.reload.title
    assert_empty post.faqs
    other = OpenBlog::SaveDraft.call({ title: "Other route", faq: [ { question: "Where?", answer: "The meadow." } ] }, actor: "Editor").post
    assert_raises(ActiveRecord::RecordNotFound) { post.update!(faqs_attributes: [ { id: other.faqs.first.id, answer: "Changed." } ]) }
    assert_equal "The meadow.", other.faqs.first.reload.answer
  end
end
