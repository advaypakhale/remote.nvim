# Security Policy

## Supported versions

Only the latest release is supported. Fixes go out as a new release rather than being backported.

## Reporting a vulnerability

Report privately through
[GitHub's security advisories](https://github.com/advaypakhale/remote.nvim/security/advisories/new), or by email to
advay.pakhale@gmail.com. Please do not open a public issue for a vulnerability.

Expect an acknowledgement within a week. If a report is valid you will be credited in the advisory unless you ask
otherwise.

## What is in scope

This plugin builds shell commands and runs them on machines you connect to, so the interesting surface is:

- **Command construction.** Every path and argument crosses a local shell, `ssh`'s argument concatenation, and the
  remote shell. An injection through a hostname, a file path, a configured `prefix`, or a tool URL is in scope.
- **Binary acquisition.** Neovim and any declared tools are fetched over HTTPS and executed on the target. Issues in
  how those are fetched, cached or verified are in scope.
- **Isolation.** The plugin is supposed to write only inside its prefix on the target and to never shadow the
  target's existing tooling. Anything that escapes the prefix is in scope.

## What is not in scope

- URLs you configure yourself in `tools`. The plugin fetches what you tell it to; verifying that source is yours.
- Trusting the target host. Connecting to a machine you do not control means running its `sh`, and it can lie to
  the plugin about anything it is asked.
- Your own Neovim config, which is copied to the target verbatim by design.
