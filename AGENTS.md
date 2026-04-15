# nvpic Agent Guide

Use this file as the development guide for automated coding agents working in this repository.

## Start Here

- Run targeted specs before broad changes, then run the full suite before claiming completion.

## Commands

| Command | Description |
|---------|-------------|
| `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/nvpic/ { minimal_init = 'tests/minimal_init.lua' }" -c qa` | Run all tests |
| `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/nvpic/<name>_spec.lua" -c qa` | Run one spec |

## Project Map

- `plugin/nvpic.lua`: defines user commands only.
- `lua/nvpic/init.lua`: public API, `setup()`, autocommands, root syncing.
- `lua/nvpic/config.lua`: config defaults and deep merge.
- `lua/nvpic/marker.lua`: parse/build `$$pic` blocks.
- `lua/nvpic/cache.lua`: image storage, hash naming, manifest, path resolution.
- `lua/nvpic/renderer.lua`: render orchestration, diagnostics, extmarks, debounced rescans.
- `lua/nvpic/treesitter.lua`: comment validation.
- `lua/nvpic/clipboard.lua`: macOS clipboard handling.
- `lua/nvpic/protocol/`: protocol registry plus Kitty implementation.
- `lua/nvpic/ui/`: paste float and built-in picker.
- `lua/nvpic/integrations/telescope.lua`: optional Telescope integration.
- `tests/nvpic/`: per-module specs.

## Development Rules

- Keep changes aligned with the existing module split; avoid broad refactors unless the task requires it.
- When adding a public behavior change, update the nearest spec and `README.md`.
- Preserve `cache.set_root(...)` synchronization from current-buffer project context when touching public entry points.
- Keep marker paths inside `pics_dir`. `cache.resolve()` now rejects escaped or out-of-scope paths.
- Preserve captured buffer/window state in async picker flows so selections write back to the buffer where the picker was opened.
- Telescope support relies on `lua/telescope/_extensions/nvpic.lua` plus the normal Telescope extension-loading path.
- Remember that clipboard support is macOS-specific.

## Style Notes

- Prefer ASCII.
- Avoid obvious inline comments.
- Do not add extra summary markdown files unless explicitly requested.

## Current Risk Areas

- Unvalidated marker `path:` values and `pics_dir` path assumptions.
- Buffer/window targeting in `ui/picker.lua` and `integrations/telescope.lua`.
- Platform-specific health reporting around `osascript`.
