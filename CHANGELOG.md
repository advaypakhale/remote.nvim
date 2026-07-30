# Changelog

## 0.1.0 (2026-07-30)


### ⚠ BREAKING CHANGES

* :RemoteSetup, :RemoteSync and :RemoteCleanup are replaced by :Remote connect and :Remote cleanup. Configuration moves to require("remote").setup(). Requires Neovim 0.11+.

### Features

* rewrite as a pure Lua plugin over a single transport primitive ([b590365](https://github.com/advaypakhale/remote.nvim/commit/b590365d2a26a9462e42df76822ba90774b88620))


### Miscellaneous Chores

* set initial release to 0.1.0 ([59ee472](https://github.com/advaypakhale/remote.nvim/commit/59ee472510d2a01b1b9473375d52791e0f108640))
