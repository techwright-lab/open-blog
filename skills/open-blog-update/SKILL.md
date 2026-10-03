---
name: open-blog-update
description: Revise or correct a public Open Blog article while preserving its publishing history.
---

Read the current post and history with `blog_get_post` and `blog_get_post_records`. Choose substantive for a meaningful content revision, correction for an error that needs a reader-visible note, or maintenance for changes that should not advance the modification date.

A public article has one content state: an update is immediately public. Present the proposed final text before calling a write tool; there is no separate preview of edits to an already-public post. Fetch the current content again if another editor may have changed it.

Show the final text to the user before publication and ask once whether they approve that exact version and have checked its facts. Include the preview link for unpublished content. Record approval only from an actual answer: send the user's name, facts_checked with their stated true or false value, and the reviewed draft's revision_identifier. For an approved public edit without a saved draft identifier, send the complete reviewed content and inline approval with the user's name and facts_checked answer, omitting approval.revision_identifier so the operation binds it to the new revision. Never attach the old public identifier to changed text. Compare the returned content with the reviewed version and report any unexpected difference. If no answer was given, omit approval. Never invent a review or a fact-check. When text changes after approval, show the new version and ask again.

Set provenance to ai_assisted if AI authored or rewrote any content, or human_written only when a person wrote all of it.

Use `blog_update_post` with the selected change type, or `blog_correct_post` with a concrete correction note. Omitted fields remain unchanged; supplied FAQ and tag lists replace their lists. Read the returned findings and revision identifier. `blog_approve_revision` records a later review only for the current public identifier; never reuse an approval for text the reviewer did not see.

Include the complete reviewed title, body, FAQ list, and image fields in the update. An inline approval without an identifier binds to the resulting revision and works when the host requires approval. Compare the returned content with the reviewed version. A separate later approval is appropriate only when publication without approval is allowed and the user has reviewed that resulting revision.
