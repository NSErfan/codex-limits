# Release workflow

- After completing a batch of fixes and improvements, commit and push the batch and publish a GitHub release with concise, user-facing notes. Do not release every intermediate edit.
- Check existing releases and tags before choosing the next version. Keep the app and widget version and build numbers aligned.
- Validate the final changes before committing. Skip the Git commit-message hook. Use a clear commit title and explain the motivation in the body.
- Release notes should summarize the main improvements and fixes, with accurate installation and validation information. Clearly identify source-only releases; attach binaries only when their build and distribution requirements have been verified.
- Publish releases to this fork, NSErfan/codex-limits, never to the upstream repository.
