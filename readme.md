# Protocol::HTTY

`protocol-htty` defines a small, terminal-safe bootstrap for carrying a raw HTTP/2 byte stream over terminal-attached sessions.

[![Development Status](https://github.com/socketry/protocol-htty/workflows/Test/badge.svg)](https://github.com/socketry/protocol-htty/actions?workflow=Test)

## Motivation

Traditional terminal user interfaces are useful, but they are also a poor fit for many modern interactions. They are constrained by character-cell rendering, limited layout semantics, awkward input models, and a presentation layer that was never designed for rich documents or structured application state.

In practice, this means TUIs often force applications into compromises: text-heavy layouts, ad-hoc protocols, and bespoke escape-sequence behavior that is hard to standardise across runtimes and terminals.

HTTY exists to keep the portability and deployment advantages of terminal workflows while avoiding the need to build an entire application model out of terminal control codes. Instead of asking the terminal stream itself to represent higher-level UI state, HTTY provides a small bootstrap that can hand a terminal session over to a normal plaintext HTTP/2 connection, enabling applications to attach browser surfaces to a normal terminal session over HTTY.

## Design

HTTY does not model application requests, regions, or resources. It transports the two directions of a single plaintext HTTP/2 (`h2c`) connection over a raw terminal-attached byte stream without introducing a second session protocol.

HTTY v1 begins with one DCS bootstrap sequence:

``` text
ESC P + H raw ESC \
```

After that bootstrap has been consumed, the session carries plain `h2c` bytes. The takeover layer intentionally stays small so it can be reimplemented in other runtimes.

## Usage

Please see the [project documentation](https://socketry.github.io/protocol-htty/) for more details.

  - [Getting Started](https://socketry.github.io/protocol-htty/guides/getting-started/index) - This guide explains how to get started with `protocol-htty` for DCS-bootstrapped raw HTTP/2 byte stream transport.

  - [HTTY Specification](https://socketry.github.io/protocol-htty/guides/specification/index) - This document specifies HTTY as a DCS-bootstrapped raw-mode takeover transport for carrying a plaintext HTTP/2 (`h2c`) connection over terminal-attached sessions.

## Releases

Please see the [project releases](https://socketry.github.io/protocol-htty/releases/index) for all releases.

### v0.3.0

  - Change `Protocol::HTTY::Stream` to take explicit input and output endpoints using `Stream.new(input, output)` and `Stream.open(input, output, **options)`.
  - Read HTTY input without buffering ahead, preserving HTTP/2 frame boundaries by reading only the announced frame payload length.

### v0.2.0

  - Add `Protocol::HTTY::Stream.open(stream, **options)` as the preferred constructor for bootstrapping HTTY over an existing stream.
  - Inline HTTY bootstrap encoding and decoding into `Protocol::HTTY::Stream`, keeping the public API focused on the single raw byte-stream abstraction used by HTTP/2.

### v0.1.0

  - Initial release.

## Contributing

We welcome contributions to this project.

1.  Fork it.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create new Pull Request.

### Running Tests

To run the test suite:

``` shell
bundle exec sus
```

### Making Releases

To make a new release:

``` shell
bundle exec bake gem:release:patch # or minor or major
```

### Developer Certificate of Origin

In order to protect users of this project, we require all contributors to comply with the [Developer Certificate of Origin](https://developercertificate.org/). This ensures that all contributions are properly licensed and attributed.

### Community Guidelines

This project is best served by a collaborative and respectful environment. Treat each other professionally, respect differing viewpoints, and engage constructively. Harassment, discrimination, or harmful behavior is not tolerated. Communicate clearly, listen actively, and support one another. If any issues arise, please inform the project maintainers.
