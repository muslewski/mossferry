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

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) preferred
(`feat:`, `fix:`, `docs:`, `chore:`).

## Pull requests

1. Branch from `main`, keep the diff focused.
2. Fill in the PR template.
3. Link issues with `Fixes #…` when applicable.
