<p align="center">
  <img height="128" alt="image" src="https://github.com/user-attachments/assets/d06f2d4d-e862-4790-be35-c8a3482ed7d1" />
</p>
<h1 align="center">Noctiluca</h1>
<p align="center">
  A New Remote Desktop for macOS<br />
  <img height="480" alt="image" src="https://github.com/user-attachments/assets/0f23f719-cc7a-42bb-ace0-61665820ddab" />
</p>

Noctiluca is a macOS-first remote desktop product family built around two apps:
Noctiluca Server, the macOS host, and Noctiluca Navigator, the client for macOS,
iOS, Windows, and Linux.

This repository is the Noctiluca monorepo. It contains the macOS Server app, the
Swift macOS/iOS Navigator app, the Sirius protocol libraries, plugin contracts,
sample plugins, and the in-progress C++/Qt Navigator client for Windows and
Linux.

Product downloads and user-facing documentation live at
[noctiluca.app](https://noctiluca.app).

## Status

Noctiluca Server is in Early Access in the `0.9.x` series. It includes the core
remote desktop, security, projection, input, clipboard, transfer, and plugin
systems, but some features are still being refined before `1.0.0`.

Noctiluca Navigator for macOS and iOS is the primary client implementation.
Navigator for Windows and Linux is being developed on the C++/Qt client stack
and is available as development/nightly builds.

AppStream, filesystem access, and some advanced plugin APIs are active
development surfaces and should be treated as experimental.

## Features

- QUIC-based Sirius protocol with independent feature channels for projection,
  input, clipboard, transfer, filesystem access, and application streaming.
- TLS 1.3 transport security, server identity validation, and known-hosts style
  certificate pinning in Navigator.
- macOS host app with menu-bar UI, onboarding, settings, authentication, input
  injection, screen capture, audio capture, and event logging.
- macOS/iOS Navigator app with SwiftUI UI, Sirius session management, HIDIO input
  sending, hardware-accelerated decoding, and multi-display session UI.
- Windows/Linux Navigator work based on the C++/Qt client stack and libsirius.
- Video projection with ScreenCaptureKit or AVFoundation capture, VideoToolbox
  H.264/H.265 encoding, hardware-accelerated platform decoders, and libvpx VP8
  support.
- Adaptive projection quality, codec negotiation, HiDPI/Retina projection, and
  multi-display support.
- Audio projection with Opus and G.711 mu-law/a-law codecs.
- Clipboard synchronization and file transfer channels.
- Filesystem access (`fsaccess`) for exposing Navigator-side files to the host,
  surfaced on macOS through a loopback NFS mount.
- Plugin bundle system for server-side extensions, including built-in PAM,
  simple password, SSH key, and debug-only null authentication plugins.
- Experimental AppStream support for streaming individual remote application
  windows instead of an entire display.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `SiriusKit/` | Shared Sirius protocol, channel, message, and transport libraries. |
| `NoctilucaServer/` | macOS host app. Accepts sessions, authenticates clients, injects input, and streams screen/audio data. |
| `NoctilucaClient/` | macOS/iOS Navigator client. Connects to hosts, sends input, and renders projection streams. |
| `NoctilucaPluginKit/` | Plugin bundle API and metadata contract for server-side extensions. |
| `SamplePluginBundle/` | Example plugin bundle project. |
| `Gesu/` | Swift macro library used for private API bindings. |
| `frameworks/` | Binary xcframework dependencies and SwiftPM wrappers, including VPX. |
| `libbcrypt/` | bcrypt support used by authentication code. |
| `NoctilucaServerTests/` | Server-side XCTest coverage. |
| `NoctilucaClientQt/` | C++/Qt Navigator client and libsirius port. |
| `docs/` | Architecture notes, audits, feature reports, and implementation plans. |
| `distutil/`, `pam.d/`, `scripts/` | Distribution, PAM, and development utilities. |

## Requirements

- macOS development machine with Xcode and Swift 6 support.
- Noctiluca Server targets macOS 15 or newer. macOS 26 or newer is recommended
  for the current settings UI.
- The Swift Navigator targets macOS and iOS/iPadOS. This checkout currently
  builds the iOS target with an iOS 18 simulator/runtime.
- SwiftPM dependency access. `SiriusKit/Package.swift` currently references a
  local `../../swift-msquic` checkout for the MsQuic wrapper.
- SwiftLint if you want to run the configured lint pass.

## Building

Use `NoctilucaServer.xcworkspace` for Xcode and command-line builds. Building
individual `.xcodeproj` files can miss workspace-level package and framework
resolution.

```bash
# macOS host
xcodebuild -workspace NoctilucaServer.xcworkspace \
  -scheme NoctilucaServer \
  -configuration Debug \
  build

# macOS Navigator client
xcodebuild -workspace NoctilucaServer.xcworkspace \
  -scheme NoctilucaClient \
  -configuration Debug \
  build

# iOS Simulator Navigator client
xcodebuild -workspace NoctilucaServer.xcworkspace \
  -scheme NoctilucaClient \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

## Testing

```bash
# Server test suite
xcodebuild -workspace NoctilucaServer.xcworkspace \
  -scheme NoctilucaServerTests \
  -configuration Debug \
  test

# A specific test class
xcodebuild -workspace NoctilucaServer.xcworkspace \
  -scheme NoctilucaServerTests \
  -only-testing:NoctilucaServerTests/AutoQualityPlannerTests \
  test
```

## Linting

```bash
swiftlint lint --config .swiftlint.yml
```

## Architecture

At a high level, a Navigator client connects to the macOS host over Sirius QUIC.
The main channel performs handshake and authentication. After authentication,
feature channels are opened for input, projection, clipboard, filesystem access,
and other capabilities.

Sirius is designed as a multi-channel remote desktop protocol rather than a
single-purpose screen stream. Its current bundled QUIC transport uses MsQuic for
the main app path, with the default Sirius port set to `8282`.

Projection is split into control and data channels. The server captures a screen
or app window, negotiates a codec, encodes frames, and streams them over a
projection data channel. The client decodes the stream and renders it through
VideoToolbox/libvpx-backed renderers. Audio follows the same channel model with
Opus or G.711 codec negotiation.

Input uses the HIDIO channel. Navigator clients send keyboard and pointer events
to the host, and the host injects them into the local macOS session.

Clipboard and large payload transfer are split as well: small clipboard payloads
travel over the clipboard channel, while larger data and files are moved through
the transfer channel.

## Security Notes

- Authentication is extensible through plugin bundles. Built-in server plugins
  cover PAM, simple password, SSH key, and debug-only null authentication.
- Navigator stores server certificate information on first connection and checks
  it on later connections to reduce the risk of man-in-the-middle attacks with
  self-signed hosts.
- Plugin bundles are loaded through a manifest and code-signing policy. Less
  isolated or unsigned/ad-hoc scenarios require explicit policy support.
- Server settings are stored under Application Support, with sensitive entries
  stored in Keychain where applicable.
- Filesystem access is opt-in and policy-gated. Host-side exposure uses a
  loopback-only NFS mount.
- AppStream is experimental and should be reviewed carefully before being used
  outside controlled development environments.

## Documentation

- [noctiluca.app](https://noctiluca.app) contains product pages, downloads,
  pricing, EULAs, and user-facing help.
- `docs/spec-violation-policy.md` defines how Sirius implementations should
  react to malformed or spec-violating messages.
- `docs/fsaccess.md` describes the host-side filesystem access design.
- `NoctilucaServer/AGENTS.md`, `NoctilucaClient/AGENTS.md`,
  `SiriusKit/AGENTS.md`, and `NoctilucaPluginKit/AGENTS.md` contain detailed
  module-specific engineering notes.
- `NoctilucaClientQt/docs/` tracks the C++/Qt client porting and audit work.

## License

Noctiluca is composed of multiple components with component-specific licenses.
See `LICENSE` for the license index, `LICENSE.server` for Noctiluca Server, and
`LICENSE.client` for Noctiluca Navigator.
