# mossferry — overview

**mossferry** is the green ferry between machines: a two-part bash tool that
opens **remote tmux sessions over mosh/ssh** with an fzf (or menu) picker.
Everyday command: **`ferry`**. Local client (`bin/mossferry`) parses config and
launches; remote brain (`bin/repo-session`) owns all tmux create/attach/claim
logic. Host-agnostic; install is npm global or repo `./install.sh` symlinks.

## Seeded zones (2026-07-21 atlas-seed)

| Slug | Purpose |
|------|---------|
| [[client]] | Local CLI — launch, doctor, update, pre-validate |
| [[repo-session]] | Remote picker / session / grid claim |
| [[green-ui]] | Vendored GREEN-UI-KIT chrome library |
| [[install-config]] | install.sh, config.example, npm package, VERSION |
| [[tests]] | Bash harness + fake tmux/mosh/ssh |
| [[demo]] | VHS demo pipeline + README GIFs |

All cards: `status: seeded`, `verifiedAt: unverified` until human review +
`atlas stamp`.

## Architecture sketch

```
local: bin/mossferry  --mosh/ssh-->  remote: bin/repo-session
         |                              |
         +-- lib/green-ui.sh -----------+
         |
   install.sh · config.example · package.json · VERSION
```
