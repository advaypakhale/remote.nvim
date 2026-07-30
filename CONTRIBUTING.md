# Contributing

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

See `:help remote-nvim-internals`. Every transport supplies one primitive, `argv(script)`, returning an argument
vector that runs a POSIX `sh` script on the target. `ssh` and `docker exec` each supply one, so neither needs its
own code path. To add a transport, implement `argv`, `label` and optionally `connect`; nothing else should change.

## Development

```sh
stylua lua plugin      # enforced in CI
typos                  # enforced in CI
```

There is no automated test suite. Verify against a real target:

```sh
docker run -d --name rnvim-dev --platform linux/amd64 debian:bookworm-slim sleep infinity
nvim -c 'Remote connect docker:rnvim-dev'
docker rm -f rnvim-dev
```

These are the paths that actually break, so exercise the relevant ones:

- A target with **neither `curl` nor `wget`** (`debian:bookworm-slim`), forcing the local-download and stream
  fallback rather than the target downloading for itself.
- A target with one of them installed, taking the other path.
- **Alpine**, which must be refused with a musl message rather than handed a glibc binary.
- A **different architecture** (`--platform linux/arm64` under qemu).
- Paths containing spaces and quotes. Every path crosses a local shell, `ssh`'s argument concatenation, and the
  remote shell, so quoting slips surface here and nowhere else.

## Pull requests

Against `main`, one logical change each. Commits follow
[Conventional Commits](https://www.conventionalcommits.org); release-please uses them to version and generate the
changelog.
