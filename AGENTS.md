# Release workflow

- After completing a batch, validate, commit, and push the changes.
- Publish a GitHub release with concise, user-facing notes when the batch changes the app's behavior, interface, or distributed build. Do not release every intermediate edit.
- For batches limited to README, documentation, screenshots, or previews, commit and push without publishing a release, creating a tag, or bumping app/widget versions or build numbers unless explicitly requested. This includes documentation and preview tooling changes that do not affect the distributed app.
- When preparing a release, check existing releases and tags before choosing the next version. Keep the app and widget version and build numbers aligned.
- Validate the final changes before committing. Skip the Git commit-message hook. Use a clear commit title and explain the motivation in the body.
- Release notes should summarize the main improvements and fixes, with accurate installation and validation information. Clearly identify source-only releases; attach binaries only when their build and distribution requirements have been verified.
- Publish releases to this fork, NSErfan/codex-limits, never to the upstream repository.
