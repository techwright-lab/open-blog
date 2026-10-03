---
name: open-blog-report
description: Inspect Open Blog diagnostics and available automated checks, then explain concrete findings and limits.
---

Start with `blog_doctor` for installation checks and `blog_check_post` for a particular article. Check `tools/list` before requesting broader reports. If `blog_get_surface_report` is available, request the relevant scope; opt into reach checks only when network checks fit the task.

Separate observed failures, warnings, skipped checks, and matters that require a person to assess. Automated checks describe observed behavior; they cannot certify editorial practices. Explain each actionable finding using the affected page or field and propose a proportionate correction.

Report only what the returned evidence supports. Do not fabricate results for unavailable tools, treat a successful HTTP response as proof of review, or silently rewrite and publish content while inspecting it.
