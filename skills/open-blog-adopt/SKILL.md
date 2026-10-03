---
name: open-blog-adopt
description: Import existing articles into Open Blog with historical evidence, reviewed FAQ extraction, and dry runs.
---

Read the source articles without changing the source system. Preserve each exact slug, source identity, original body, and available historical records. Use `blog_extract_faq` to propose a separate FAQ list. Before applying a proposal, check that each answer is complete, the suggested cuts remove only FAQ content, the remaining body reads correctly, internal links still work, and the body does not duplicate the stored FAQ. Review ambiguous classifications with the user. Store source_body_sha256 when the submitted body differs from the original.

Ask whether the original system has an approval record for the imported article. Use imported_approval only with its reviewer, original time, evidence, and the person confirming that it covers this content. Otherwise, record a declaration only when the user supplies the reviewer, approval time, facts_checked answer, declaration date, and their own name. Ask for a declared first publication date when historical evidence is missing, and place that answer in declaration.declared_first_published_at. Do not send approval in an adoption request or invent historical evidence or declarations.

Use `blog_adopt_post` with dry_run true first. Inspect the proposed full article, notices, records, and redirects. A complete snapshot replaces omitted FAQ and tag lists with empty lists; send every field that must survive. Missing evidence leaves historical dates unknown. Do not assign today's date as an invented publication date.

After reviewing the dry-run result, import within the user's authorized migration scope. Check article totals, slugs, redirects, images, FAQ records, and notices. Reusing a source pair updates that import only until later publishing activity makes replacement unsafe; investigate an already_changed_in_gem refusal instead of forcing it.
