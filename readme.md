# Protocol::HTTY

`protocol-htty` defines a small, terminal-safe framing layer for carrying an opaque byte stream over TTY side channels.

[![Development Status](https://github.com/socketry/protocol-htty/workflows/Test/badge.svg)](https://github.com/socketry/protocol-htty/actions?workflow=Test)

## Design

HTTY does not model application requests, regions, or resources. It transports the two directions of a single plaintext HTTP/2 (`h2c`) connection over terminal-safe chunks without introducing a second session protocol.

Each chunk is encoded as a DCS sequence:

``` text
ESC P HTTY;1;BASE64_CHUNK ESC \
```

The framing layer intentionally stays small so it can be reimplemented in other runtimes.

## Guides

- [Getting Started](guides/getting-started/readme.md)
- [Specification](guides/specification/readme.md)

## Usage

The low-level API is intentionally small. `{Protocol::HTTY::Framer}` reads and writes HTTY chunks, while `{Protocol::HTTY::Stream}` exposes an opaque byte stream on top of those chunks.

### Framing Individual Chunks

``` ruby
require "stringio"
require "protocol/htty"

output = StringIO.new
framer = Protocol::HTTY::Framer.new(StringIO.new, output)

framer.write_chunk("hello")

output.string
# => "\ePHTTY;1;aGVsbG8=\e\\"
```

### Streaming Opaque Bytes

``` ruby
require "stringio"
require "protocol/htty"

transport = StringIO.new
writer = Protocol::HTTY::Stream.new(StringIO.new, transport, packet_size: 4)

writer.write("hello world")
writer.close

transport.rewind
reader = Protocol::HTTY::Stream.new(transport, StringIO.new)

reader.read(11)
# => "hello world"
reader.read
# => nil
```

This transport layer does not interpret the payload beyond chunk framing. Higher-level code can carry the two directions of a plaintext HTTP/2 connection over the resulting byte streams.

## Releases

There are no documented releases.

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
