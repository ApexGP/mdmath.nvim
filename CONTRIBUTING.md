# Contributing

## Tests

```sh
make test    # headless Lua specs (one Neovim process per spec) + node IPC/unit tests
make bench   # viewport scan cost on a synthetic document
```

The render spec needs `node`, `rsvg-convert`, ImageMagick and `mdmath-js/node_modules`
(`:MdMath build`). Without them it is skipped, not failed. Terminal capabilities are probed
with `python3 tests/manual/kitty-probe.py`; the manual checklist is
`tests/manual/mdmath-test.md`.

## Wire format

The Lua client and the node processor share a byte-oriented wire format. If you change any field order or meaning, bump `PROTOCOL_VERSION` in both `lua/mdmath/Processor.lua` and `mdmath-js/src/processor.js` — the processor refuses to start on a mismatch.

## Static checks

`.luarc.json` configures lua-language-server for the repository (LuaJIT runtime, the Neovim runtime via `${env:VIMRUNTIME}`, `vim` as a known global). The sources are annotated with LuaCATS; with `lua-language-server` on `PATH`, run `lua-language-server --check=. --checklevel=Warning` to verify the annotations.

## Versioning and releases

The plugin version lives in `lua/mdmath/version.lua`. `mdmath-js/package.json` and `package-lock.json` must match it (a test enforces this), and a release tag must match it after dropping the `v` prefix and any prerelease suffix (the Release workflow enforces this).

Releases are cut by pushing a `v*` tag: the `Release` workflow publishes a GitHub release with generated notes. Nothing is compiled or bundled — the repository is the artifact, and `mdmath-js` dependencies are installed by users through `:MdMath build`.
