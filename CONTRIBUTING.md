# Contributing to mossferry

Thanks for wanting to help.

## Community

| Kind | Where |
|---|---|
| Questions, ideas, show-and-tell | [Discussions](https://github.com/muslewski/mossferry/discussions) |
| Bugs & concrete feature requests | [Issues](https://github.com/muslewski/mossferry/issues/new/choose) |
| Security | [SECURITY.md](./SECURITY.md) — private only |

Please follow the [Code of Conduct](./CODE_OF_CONDUCT.md).

## Dev setup

```bash
git clone https://github.com/muslewski/mossferry.git
cd mossferry
npm install -g .   # or: ./install.sh
```

## Checks

```bash
bash tests/run.sh
bash -n bin/mossferry bin/repo-session
```

### Notes

- Install must work on **both shores** (local client + remote `repo-session`).
- Keep `config.example` in sync with documented `FERRY_*` keys.
- Prefer hermetic tests under `tests/` with fakes over live ssh.

## Project mind (informal knowledge base)

This repository keeps a small **[memory-atlas](https://github.com/muslewski/memory-atlas)** vault
(`mossferry-mind/` at the repo root) — plain markdown that maps architecture for **humans and coding agents**.

| | |
|--|--|
| **Convention** | Informal and optional for tiny fixes — **appreciated** when you change how a subsystem works |
| **Why** | Better orientation, higher-quality agent-assisted edits, less “where does this live?” thrash |
| **Not npm** | The mind is **git-only**. It is not shipped in this project’s npm package (if any), and not downloaded when someone installs the separate `memory-atlas` CLI |

**How (when it matters):** open `mossferry-mind/map/index.md` → read the zone you touch → update that zone if ownership or invariants moved → optional `npx memory-atlas stamp <slug>` after you verified → `npx memory-atlas build`. Honest short notes beat silence or fake stamps.

Skip without guilt for typos and drive-by nits. Prefer leaving a PR note if the mind should be updated later rather than inventing ceremony.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) preferred
(`feat:`, `fix:`, `docs:`, `chore:`).

## Pull requests

1. Branch from `main`, keep the diff focused.
2. Fill in the PR template.
3. Link issues with `Fixes #…` when applicable.
