---
layout: default
title: MCP and agents
nav_order: 6
permalink: /mcp/
---

# MCP and agents

MCP is available at `/blog/mcp`, using the same Bearer authentication as the API. Send JSON-RPC requests by POST, for example `{"jsonrpc":"2.0","id":1,"method":"tools/list"}`. Notifications return 202 without a body; GET and DELETE return 405. Browser origins must match the request origin or configured public origin, including the port. Set `config.mcp.enabled = false` to disable the endpoint. Each HTTP request uses the shared actor rate limit once.

| MCP tools | Purpose |
| --- | --- |
| `blog_list_posts`, `blog_search_posts`, `blog_get_post` | Find and read stored articles |
| `blog_get_post_records`, `blog_check_post`, `blog_doctor` | Inspect history, findings, and setup |
| `blog_save_draft`, `blog_get_preview_link` | Save unpublished content and obtain its preview |
| `blog_publish_post`, `blog_update_post`, `blog_correct_post`, `blog_approve_revision` | Release, revise, correct, or record a review |
| `blog_declare_connections`, `blog_unpublish_post`, `blog_remove_post` | Declare relationships, withdraw, or remove content |
| `blog_upload_image` | Import a URL or upload base64 bytes with filename and content type |
| `blog_list_categories`, `blog_save_category`, `blog_list_tags` | Manage post classification |
| `blog_list_authors`, `blog_save_author`, `blog_list_series`, `blog_save_series` | Manage authors and series |
| `blog_list_redirects`, `blog_save_redirect` | Inspect or create URL moves and removals |
| `blog_extract_faq`, `blog_adopt_post` | Prepare FAQ extraction and import existing articles |
| `blog_get_site_page`, `blog_save_site_page` | Read or edit a policy page by `kind` |
| `blog_get_page_views` | Read daily article counts or top articles |
| `blog_get_surface_report` | Inspect fetched reader pages and publishing records |

Tools use the fields in the [JSON API reference]({% link api.md %}). Pass `id` for a specific post; publish accepts an optional ID, and draft saves use slug or external-ID upsert. Category, author, and series saves use an optional numeric ID to select an update. Redirect save creates a new record. Correction always selects the correction change type and requires a note. Image upload takes either `{url}` or `{base64, filename, content_type}`. MCP list sizes are additionally capped by `config.mcp.max_page_size` (default 50).

Hosts can add `OpenBlog::Mcp.tools` to their own `MCP::Server`, supplying `actor` and optionally `base_url` in its server context. `OpenBlog::Mcp.definitions` exposes each tool's name, title, description, schema, annotations, scope, and `call(arguments, actor:, base_url: nil)` method. Use an `OpenBlog::Actor` with explicit scopes. Direct Ruby calls retain validation and permission checks; the embedding host manages its own request rate limiting. Tool results contain the same JSON object in text content and structured content, with `isError` set for typed refusals.

## Packaged agent workflows

The gem ships six agent workflows in `OpenBlog::Engine.root.join("skills")`: install, publish, update, adopt, policy pages, and reports. They describe approval and evidence handling and check tool availability for features added by later versions.

## Publishing instructions

Show the final text to the user before publication and ask once whether they approve that exact version and have checked its facts. Include the preview link for unpublished content. Record approval only from an actual answer: send the user's name, facts_checked with their stated true or false value, and the reviewed draft's revision_identifier. For an approved public edit without a saved draft identifier, send the complete reviewed content and inline approval with the user's name and facts_checked answer, omitting approval.revision_identifier so the operation binds it to the new revision. Never attach the old public identifier to changed text. Compare the returned content with the reviewed version and report any unexpected difference. If no answer was given, omit approval. Never invent a review or a fact-check. When text changes after approval, show the new version and ask again.

Set provenance to ai_assisted if AI authored or rewrote any content, or human_written only when a person wrote all of it.

## Import instructions

Ask whether the original system has an approval record for the imported article. Use imported_approval only with its reviewer, original time, evidence, and the person confirming that it covers this content. Otherwise, record a declaration only when the user supplies the reviewer, approval time, facts_checked answer, declaration date, and their own name. Ask for a declared first publication date when historical evidence is missing, and place that answer in declaration.declared_first_published_at. Do not send approval in an adoption request or invent historical evidence or declarations.

See [publishing]({% link publishing.md %}) for preview and scheduling behavior and [adoption]({% link adoption.md %}) for historical evidence.
