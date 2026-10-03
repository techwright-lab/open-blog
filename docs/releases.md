---
layout: default
title: Releases
nav_order: 14
permalink: /releases/
---

# Releases

Releases use two manual GitHub Actions workflows. **Prepare Release** updates the version and changelog in a pull request. **Publish** uses the reviewed, tested main commit to publish to RubyGems and create or update its GitHub Release. Ordinary merges do not publish a gem.

## First-time setup

In the repository's Actions settings, allow GitHub Actions to create pull requests. The preparation workflow uses the repository's `GITHUB_TOKEN` and explicitly starts the CI, Installer, and Docs checks for its release branch.

Create a GitHub environment named `release`, restrict deployment to `main`, and add an approving reviewer. Configure a RubyGems trusted publisher with these values:

| Field | Value |
| --- | --- |
| Gem name | `open_blog` |
| Repository owner | `techwright-lab` |
| Repository name | `open-blog` |
| Workflow filename | `publish.yml` |
| Environment | `release` |

For the first publication, create a **pending trusted publisher** in the intended gem owner's RubyGems account. For an existing gem, use its Trusted publishers settings. The workflow exchanges GitHub's identity token for short-lived RubyGems credentials; no long-lived API key is stored in GitHub. See the [RubyGems Trusted Publishing guide](https://guides.rubygems.org/trusted-publishing/).

## Prepare a version

1. Add meaningful entries under **Unreleased** in `CHANGELOG.md` and merge the changes.
2. In GitHub Actions, run **Prepare Release** on `main`, supplying a stable version such as `0.1.1`.
3. Review the generated pull request. It changes `lib/open_blog/version.rb` and moves Unreleased notes into a dated changelog section. The initial, undated `0.1.0` entry can be finalized using `0.1.0` as the input.
4. Let CI, Installer, and Docs pass, review the diff, and merge the pull request.

Preparation refuses published versions, downgrades, and conflicting release branches. Repeating the same request reuses a matching open pull request. If main has moved or someone has edited that release branch, review the branch manually rather than overwriting it.

## Publish

Wait for **CI**, **Installer**, and **Docs** to succeed on the resulting `main` commit. Then run **Publish** on `main`, supplying the prepared version and its full 40-character commit SHA. Approve the `release` environment deployment when GitHub requests it.

The workflow checks the commit, dated changelog entry, successful checks, and release-tag history. It builds the gem reproducibly and compares it with any existing RubyGems artifact. A different artifact under the same version is refused. When the version is new, the workflow publishes it through Trusted Publishing.

After confirming the published bytes, it creates the version tag and GitHub Release using the changelog's release notes. If the matching GitHub Release already exists, it synchronizes the notes and title and marks it as a published stable release. A retry preserves an identical published gem and refuses a tag pointing to another commit.

If RubyGems publication succeeds but a later GitHub step fails, retry the same version and commit while that commit remains `main`. The artifact check prevents a duplicate upload, and the workflow can complete the missing tag or release update. If the repository has advanced, investigate the failed release before preparing another version.
