---
name: open-blog-policy-pages
description: Prepare accurate editorial policy pages for an Open Blog publisher from the publisher’s own answers.
---

Use `blog_doctor` to inspect policy links. Read existing pages with `blog_get_site_page`, passing `kind`: `responsible_party`, `corrections`, `editorial`, or `ai_use`. A missing page returns `not_found`; start with the publisher’s answers below.

Ask for the accountable publisher and contact route, correction handling and reader reports, editorial selection and review practices, and how AI is used. Write only practices the user confirms. Reuse an existing host policy URL when that is the user's chosen source.

Show the final pages for approval before publishing. Use `blog_save_site_page` with `kind`, `title`, Markdown `body`, and `status: "draft"` while preparing text. After approval, save `status: "published"` with the actual `approved_by` name and ISO date `approved_on`; this requires both write and publish scopes. Do not fill approval fields from assumptions. Verify the published links and rendered text.
