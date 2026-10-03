---
name: open-blog-publish
description: Draft, review, publish, or schedule an Open Blog article using revision-bound approval.
---

Use `blog_search_posts` to check for existing coverage. Reuse or upload images with `blog_upload_image`; put their returned URLs in the body. Supply alternative text and keep FAQ answers as plain text.

Save with `blog_save_draft`, inspect the returned findings, and correct the draft before asking for approval. Use the returned preview URL or `blog_get_preview_link` so the user sees the version being reviewed. Keep its revision identifier with the answer.

Show the final text to the user before publication and ask once whether they approve that exact version and have checked its facts. Include the preview link for unpublished content. Record approval only from an actual answer: send the user's name, facts_checked with their stated true or false value, and the reviewed draft's revision_identifier. For an approved public edit without a saved draft identifier, send the complete reviewed content and inline approval with the user's name and facts_checked answer, omitting approval.revision_identifier so the operation binds it to the new revision. Never attach the old public identifier to changed text. Compare the returned content with the reviewed version and report any unexpected difference. If no answer was given, omit approval. Never invent a review or a fact-check. When text changes after approval, show the new version and ask again.

Set provenance to ai_assisted if AI authored or rewrote any content, or human_written only when a person wrote all of it.

Call `blog_publish_post` only within the user's publication request. Include the recorded approval when available; do not turn an unanswered fact-check question into true. A future `publish_at` schedules the post. Check the response state, notices, and findings; a schedule is not confirmation that the article is already public.
