---
layout: default
title: Releases
nav_order: 15
permalink: /releases/
---

# Releases

One GitHub Actions workflow, **Publish**, releases the gem. It starts by itself after **CI**, **Installer**, and **Docs** finish on a `main` push. It publishes only when the version in `lib/open_blog/version.rb` has no release tag yet and all three checks pass on that commit. Ordinary merges do not publish a gem, and no one starts or approves a run.

## First-time setup

Create a GitHub environment named `release` and restrict deployment to `main`. Do not add required reviewers: a reviewer makes every release wait for approval. Configure a RubyGems trusted publisher with these values:

| Field | Value |
| --- | --- |
| Gem name | `open_blog` |
| Repository owner | `techwright-lab` |
| Repository name | `open-blog` |
| Workflow filename | `publish.yml` |
| Environment | `release` |

For the first publication, create a **pending trusted publisher** in the intended gem owner's RubyGems account. For an existing gem, use its Trusted publishers settings. The workflow exchanges GitHub's identity token for short-lived RubyGems credentials; no long-lived API key is stored in GitHub. See the [RubyGems Trusted Publishing guide](https://guides.rubygems.org/trusted-publishing/).

## Release a version

1. In a pull request, change `VERSION` in `lib/open_blog/version.rb` to a stable version such as `0.3.2`.
2. In the same pull request, rename the `## [Unreleased]` heading in `CHANGELOG.md` to `## [0.3.2] - YYYY-MM-DD` with the release date, and add a new empty `## [Unreleased]` heading above it.
3. Merge the pull request after review and successful checks.

CI runs `ruby bin/release-check notes` on every pull request. It fails when the changelog has no dated entry with notes for the version in `lib/open_blog/version.rb`. You cannot merge a version change without its release notes.

## What Publish does

Each of CI, Installer, and Docs starts Publish when it finishes successfully on a `main` push. A first **check** job reads the version from the commit:

- If the version tag already exists on another commit, the version did not change. The run stops without a release.
- If a check is still running on the commit, the run stops without a release. The last check to finish starts the run that releases.
- If a finished check failed, the commit is no longer on `main`, or a newer release tag exists, the run fails.

When the check job finds an unreleased version with three passing checks, the **publish** job builds the gem reproducibly and compares it with any existing RubyGems artifact. A different artifact under the same version is refused. When the version is new, the job publishes it through Trusted Publishing. After confirming the published bytes, it creates the version tag and a GitHub Release with the changelog's notes for that version. If the matching GitHub Release already exists, it synchronizes the notes and title and marks it as a published stable release.

## Retry a failed release

If RubyGems publication succeeds but a later GitHub step fails, open the failed **Publish** run and choose **Re-run failed jobs**. The artifact check prevents a duplicate upload, and the run completes the missing tag or release update. Re-running a failed CI, Installer, or Docs run on the release commit also starts Publish again.
