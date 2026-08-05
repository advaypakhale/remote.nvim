# Contributing

## Scope

remote.nvim is meant to be complete. Bug fixes are welcome. New features mostly are not — the plugin is one
readable file, so fork it. Changes that add a dependency, assume anything about the target beyond a POSIX shell
and `tar`, or special-case a plugin manager will not be accepted.

## Architecture

The plugin is one file, `lua/remote/init.lua`, ordered so it reads top to bottom; its header comment is the
overview. `lua/remote/ssh_config.lua` parses ssh configs for completion, and `plugin/remote.lua` defines
`:Remote`.

A transport is a table of closures over one target: `argv(script)` returns an argument vector that runs a POSIX
`sh` script there; `ssh` and `docker exec` both do this. To add a transport, write a constructor alongside
`ssh_transport` and `docker_transport` and extend `resolve`.
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
