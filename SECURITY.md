# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| latest on main / npm latest | Yes |
| older | No — please upgrade first |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report privately via
[GitHub's private security advisory](https://github.com/muslewski/mossferry/security/advisories/new)
or email **10kento10@gmail.com** with the subject line `[SECURITY] mossferry`.

Include:

- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fix (optional)

You will receive a response within **72 hours**. We aim to ship a patch within
**14 days** of a confirmed vulnerability.

## Scope

mossferry is a local bash client that launches mosh/ssh and a remote session picker. Primary risk: command injection via host/repo args, unsafe ssh options, or symlink attacks during install.sh.

Out of scope: issues in Node.js / Python / the OS, third-party CLIs this tool
launches, or GitHub Actions runners themselves.
