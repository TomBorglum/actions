# Changelog

## [2.0.0](https://github.com/TomBorglum/actions/compare/v1.0.0...v2.0.0) (2026-10-14)


### ⚠ BREAKING CHANGES

* `use pixi` now requires a pinned version as its first argument, so the template moves to second: `use pixi 0.81.0 python`. An .envrc using the old unversioned form fails the action. A workspace whose committed pixi.lock has drifted from its pixi.toml now also fails, where previously the lockfile was rewritten in place.

### Features

* require a pinned pixi version in the use pixi directive ([#5](https://github.com/TomBorglum/actions/issues/5)) ([0a7265a](https://github.com/TomBorglum/actions/commit/0a7265adbbf1f51082acc9b098338d6fd590a91c))


### Dependencies

* bump direnv to v2.38.2 ([#4](https://github.com/TomBorglum/actions/issues/4)) ([acef68e](https://github.com/TomBorglum/actions/commit/acef68e447d98b6d760a2e9e113a54eb068c62ac))

## 1.0.0 (2026-10-09)


### Features

* add setup-direnv action ([#2](https://github.com/TomBorglum/actions/issues/2)) ([1b84d19](https://github.com/TomBorglum/actions/commit/1b84d197319b7012a8684d29b23906a6cc3741bf))
