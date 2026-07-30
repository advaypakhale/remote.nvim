<!--
The PR title must follow Conventional Commits, e.g. "fix: resolve Include globs
relative to ~/.ssh". CI checks this, and it decides the next release.
-->

## What and why

<!-- What changes, and what problem it solves. Link any issue with "Fixes #123". -->

## How it was verified

<!--
There is no automated test suite, so say what you ran this against. For example:
"debian:bookworm-slim (no curl or wget), and alpine to confirm it is still refused."
-->

## Checklist

- [ ] `stylua lua plugin` produces no changes
- [ ] Verified against a real target, described above
- [ ] Holds the [design constraints](../blob/master/CONTRIBUTING.md#design-constraints), or explains why not
- [ ] `doc/remote-nvim.txt` updated if behaviour or configuration changed
