# Contributing To VansonMod

Thanks for helping improve VansonMod.

## Project Scope

VansonMod is a general iOS debugging utility for security research, reverse engineering learning, and compliant technical testing.

Accepted contributions should keep the project general-purpose:

- Improvements to memory search, memory browsing, pointer workflows, RVA workflows, scripting, archive management, localization, documentation, build scripts, and UI quality.
- Fixes for crashes, incorrect results, performance issues, compatibility issues, and accessibility issues.
- General abstractions that help multiple apps or environments.

Contributions should avoid target-specific behavior:

- No presets, workflows, bypasses, or dedicated logic for a specific app, game, service, or commercial target.
- No bundled target data, account data, private keys, certificates, profiles, or proprietary assets.
- No generated build products such as `.theos/`, `packages/`, `release/`, `Payload/`, `.deb`, `.tipa`, or `.ipa`.

## Build Checks

Before opening a pull request, run:

```sh
make clean package FINALPACKAGE=1 DEBUG=0
```

For release packaging:

```sh
./scripts/release.sh
```

## Code Guidelines

- Keep changes focused and easy to review.
- Follow the existing Objective-C++, C++, and Theos project style.
- Keep VansonMod and VansonLoader release flows independent.
- Add or update localized strings when UI text changes.
- Update README or docs when behavior, build steps, release output, or supported scope changes.

## License

By contributing, you agree that your contribution is provided under GPL-3.0, the same license as this project.

