---
name: open-blog-policy-pages
description: Prepare accurate editorial policy pages for an Open Blog publisher from the publisher’s own answers.
---

Use `blog_doctor` to inspect configured policy links and `tools/list` to see which page operations the installed version supports. If page tools are absent, prepare the text and report that publishing it requires a version with page editing. Do not claim that a draft has been published.

Ask for the accountable publisher and contact route, correction handling and reader reports, editorial selection and review practices, and how AI is used. Write only practices the user confirms. Reuse an existing host policy URL when that is the user's chosen source.

Show the final pages for approval before publishing. When available, `blog_get_site_page` reads existing content and `blog_save_site_page` stores the approved text with the actual reviewer and date. Do not fill approval fields from assumptions. Verify the published links and rendered text.
