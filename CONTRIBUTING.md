# Contributing

Thanks for taking the time. This is a deliberately small plugin, so the bar for new code is "does it hold the
constraints below" rather than "is it useful to someone".

## Design constraints

These are the point of the project. A change that breaks one needs a very good reason.

1. **Low dependency.** `ssh` and `curl` locally; `sh` and `tar` on the target. Nothing else may become required.
2. **No client/server split.** Neovim runs on the target as an ordinary terminal program.
3. **Nothing is assumed about the target.** No package manager, no root, no bash, no particular architecture.
4. **Nothing is assumed about your config.** It is an opaque tree of bytes. No code may know what a plugin manager
   is, or special-case one.
5. **Nothing outside the prefix is written.** All four XDG directories are redirected, and system tooling on the
   target is never shadowed.
6. **Prefer fewer branches.** Where a case needs special handling, failing with a clear message usually beats
   quietly doing something subtly wrong.

## Architecture

`:help remote-nvim-internals` describes how it works. The short version: every transport supplies one primitive,
`argv(script)`, returning an argument vector that runs a POSIX `sh` script on the target. `ssh` and `docker exec`
each supply one, so neither needs its own code path. Everything else is built on that.

If you are adding a transport, implement `argv`, `label` and optionally `connect`, and nothing else should need to
change.

## Commits and pull requests

Commit messages and PR titles follow [Conventional Commits](https://www.conventionalcommits.org). CI validates the
PR title, and [release-please](https://github.com/googleapis/release-please) turns merged commits into the
changelog and the next version, so the prefix decides the release:

| Prefix                | Effect                          |
| --------------------- | ------------------------------- |
| `fix:`                | patch release                   |
| `feat:`               | minor release                   |
| `!` or `BREAKING CHANGE:` | major release               |
| `docs:` `chore:` `ci:` `refactor:` `style:` `perf:` `test:` `build:` `revert:` | no release |

Keep the subject lowercase and imperative: `fix: resolve Include globs relative to ~/.ssh`.

Open a pull request against `master`. One logical change per PR.

## Before you push

```sh
stylua lua plugin      # formatting is enforced in CI
typos                  # spelling is enforced in CI
```

There is no automated test suite. Verify changes against a real target, which is easiest in a container:

```sh
docker run -d --name rnvim-dev --platform linux/amd64 debian:bookworm-slim sleep infinity
nvim -c 'Remote connect docker:rnvim-dev'
docker rm -f rnvim-dev
```

Worth exercising when you touch the relevant area, because these are the paths that break:

- A target with **neither `curl` nor `wget`** (`debian:bookworm-slim` is one), which forces the local-download and
  stream fallback rather than the target downloading for itself.
- A target with one of them installed, which takes the other path.
- **Alpine**, which must be refused with a clear musl message rather than handed a glibc binary.
- A **different architecture** (`--platform linux/arm64` under qemu).
- Paths containing spaces and quotes. Every path crosses a local shell, `ssh`'s argument concatenation, and the
  remote shell, so quoting slips surface here and nowhere else.

## Reporting bugs

Include the output of `:checkhealth remote`, the target's `uname -sm`, and whether the target has `curl` or `wget`.
Those three answers determine which code path ran.
