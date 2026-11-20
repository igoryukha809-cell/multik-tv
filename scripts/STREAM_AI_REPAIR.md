# Stream auto-diagnostics and AI repair

The repository includes two layers:

- `scripts/stream_autorepair.py` checks the Render health endpoint, HLS playlist, and up to five recent media segments.
- `scripts/ai_stream_repair.py` sends the diagnostic report and a limited set of source files to the OpenAI Responses API. It accepts only a unified diff for two allowlisted files, checks the patch with `git apply --check`, and applies it only in the temporary GitHub Actions workspace.
- `.github/workflows/stream-runtime-autodiagnostics.yml` runs every five minutes and can also be started manually from GitHub Actions.

## Required GitHub Actions secret

Add `OPENAI_API_KEY` as a repository Actions secret for AI analysis. The key is used only by the workflow and must never be committed to the repository or pasted into chat.

Optional: add `RENDER_API_KEY` if a future recovery step is explicitly configured to request a Render redeploy. The current workflow does not automatically deploy AI changes.

## Safety and deployment

The AI agent cannot modify workflow files, secrets, deployment permissions, or arbitrary project files. It proposes changes only to:

- `stream-server/render-start.sh`
- `scripts/stream_autorepair.py`

The workflow runs Python compilation, shell syntax checks, and unit tests before opening a pull request. Review and merge the pull request only after the checks pass. A pull request is not proof that the public stream is playing; verify the actual player and HLS output separately.
