# Security Policy

## Supported Versions

Security reports are accepted for the current public 2.9 source line.

## Reporting A Vulnerability

Please report security issues privately before public disclosure.

Use one of these channels:

- GitHub Security Advisories, when available on the repository.
- Telegram: `@VansonMod`

Include:

- Affected version or commit.
- Device and iOS environment.
- Steps to reproduce.
- Expected and actual behavior.
- Crash logs, screenshots, or proof-of-concept details when safe to share.

## Scope

In scope:

- Crashes or memory corruption in VansonMod.
- Unsafe file import/export behavior.
- Incorrect handling of untrusted `.vm`, `.vmsc`, or related project files.
- Build or release script issues that can leak local files or package unintended content.

Out of scope:

- Reports about using the tool against a third-party target without authorization.
- Requests for target-specific bypasses, presets, or private adaptations.
- Issues caused by modified builds that cannot be reproduced from this source tree.

## Disclosure

Please allow time for review and a fix before public disclosure.

