# Contributing

## Scope

remote.nvim aims to stay small. It needs `ssh` and `curl` locally, and only `sh` and `tar` on the target. Changes
that add a required dependency, assume something about the target, or add support for a specific plugin manager are
unlikely to be accepted.

## Architecture

Each transport provides `argv(script)`, returning an argument vector that runs a POSIX `sh` script on the target;
`ssh` and `docker exec` both do this. To add a transport, implement `argv`, `label` and optionally `connect`.
`:help remote-nvim-layout` describes what is installed on the target.

## Development

```sh
stylua lua plugin
typos
```

Both are checked in CI.

There is no test suite, so verify against a real target. A container is easiest:

```sh
docker run -d --name rnvim-dev --platform linux/amd64 debian:bookworm-slim sleep infinity
nvim -c 'Remote install docker:rnvim-dev'
docker rm -f rnvim-dev
```

Worth checking when you touch the relevant code:

- A target with neither `curl` nor `wget` (`debian:bookworm-slim`), and one with either installed. These take
  different download paths.
- A different architecture (`--platform linux/arm64` under qemu).
- Paths containing spaces and quotes. Every path crosses a local shell, `ssh`'s argument concatenation, and the
  remote shell.

## Pull requests

Against `main`, one logical change each. Commits follow
[Conventional Commits](https://www.conventionalcommits.org).
