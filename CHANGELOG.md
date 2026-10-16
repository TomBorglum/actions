# Changelog

## [3.0.0](https://github.com/TomBorglum/actions/compare/v2.1.0...v3.0.0) (2026-10-16)


### ⚠ BREAKING CHANGES

* every action moved. `setup-direnv` is now `direnv/setup`, `update-pixi-dependencies` is now `pixi/upgrade-dependencies`, and `direnv/update-pixi` is now `direnv/upgrade-pixi`. The old paths are gone, so a workflow pinned to one fails to resolve an action rather than running old code - update the path and the pin to `@v3` together. The toolchain cache key changed from `setup-direnv-toolchains-` to `direnv-setup-toolchains-`, so the first run after upgrading repopulates the cache.

### Features

* add direnv/update-pixi action ([#12](https://github.com/TomBorglum/actions/issues/12)) ([8e3b31e](https://github.com/TomBorglum/actions/commit/8e3b31e8d2a5f90efcdf808e9fa966708e2b6b81))
* group every action under its domain and name the pixi actions upgrade ([#14](https://github.com/TomBorglum/actions/issues/14)) ([4163a99](https://github.com/TomBorglum/actions/commit/4163a99288f94d64e604d2ab3e7e3d997eeddda1))

## [2.1.0](https://github.com/TomBorglum/actions/compare/v2.0.0...v2.1.0) (2026-10-15)


### Features

* add update-pixi-dependencies action ([#8](https://github.com/TomBorglum/actions/issues/8)) ([bfcea93](https://github.com/TomBorglum/actions/commit/bfcea939f4d228cabc47ae16509ea865d2ddf03f))

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
