# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Noctiluca, please report it by email:

<contact+nocsecurity@unstabler.pl>

Please do not report security vulnerabilities through public GitHub issues, Discord, or other public channels before we have had a reasonable opportunity to investigate and address the issue.

Including the following information will help us respond promptly:

- A detailed description of the vulnerability
- Steps to reproduce the issue
- Affected product, component, and version information
- Relevant environment details, such as OS version and build type
- Any proof-of-concept code, logs, crash reports, or screenshots that help demonstrate the issue

Please redact secrets, credentials, private keys, personal data, and unrelated user data from any materials you send.

## Scope

This policy covers security issues in this repository, including:

- Noctiluca Server
- Noctiluca Navigator / Noctiluca Client components maintained in this monorepo
- SiriusKit protocol, channel, and transport code
- NoctilucaPluginKit and bundled plugin-hosting code
- Supporting tools, daemons, and generated protocol bindings that are part of this repository

For ordinary bugs, feature requests, purchase questions, or general support, please use the normal support contact:

<contact@unstabler.pl>

## Supported Versions

Noctiluca is currently in Early Access. Security fixes are generally prioritized for the latest public release and the active development branch. Older releases may receive fixes at the maintainers' discretion, depending on severity, exploitability, and release constraints.

Users are encouraged to update to the latest available version to receive security fixes.

## Disclosure Process

We kindly ask that you follow responsible disclosure principles when reporting security vulnerabilities:

- Give us a reasonable amount of time to investigate, fix, and release updates before public disclosure.
- Avoid accessing, modifying, or deleting data that does not belong to you.
- Avoid disrupting users, services, or development infrastructure.
- Avoid social engineering, phishing, physical attacks, or attacks against third-party services.

After receiving a report, we will review the issue, assess its severity, and coordinate with the reporter when additional information or disclosure timing is needed.

## Bug Bounty

We do not currently operate an official bug bounty program. However, we are always grateful for security vulnerability reports, and we may consider appropriate compensation for critical vulnerabilities at our discretion. Please inquire when submitting a security report for more details.
