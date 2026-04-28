# Getting Started

This guide explains how to get started with `protocol-htty` for terminal-safe HTTP/2 byte stream transport.

## Installation

Add the gem to your project:

~~~ bash
$ bundle add protocol-htty
~~~

## Why HTTY Exists

When you need to carry an `h2c` connection over stdin/stdout, PTYs, or SSH sessions, raw HTTP/2 bytes are not safe to write directly into the terminal stream. Control bytes can interfere with terminal parsing, corrupt visible output, or be truncated by terminal-oriented infrastructure.

Use `protocol-htty` when you need:

- **Terminal-safe transport**: Carry arbitrary HTTP/2 bytes through terminal channels without rendering control data.
- **A small framing layer**: Encode and decode byte chunks without introducing a second application protocol.
- **Cross-runtime interoperability**: Keep the framing simple enough to reimplement in other languages or environments.

Without HTTY, higher-level systems would need to invent their own ad hoc framing and decoding rules before they could safely carry HTTP/2 over terminal I/O.

## Core Concepts

- {ruby Protocol::HTTY::Framer} encodes and decodes individual HTTY chunks.
- {ruby Protocol::HTTY::Stream} reconstructs an opaque byte stream on top of HTTY chunks.
- HTTY transports bytes only. HTTP/2 connection setup, stream lifecycle, and shutdown semantics remain owned by HTTP/2.

## Usage

The low-level API is intentionally small. Start with {ruby Protocol::HTTY::Framer} if you need direct control over individual chunks, or use {ruby Protocol::HTTY::Stream} if you want an opaque byte stream interface.

### Framing Individual Chunks

If you are integrating HTTY into an existing transport, start with the framer. This gives you direct access to the terminal-safe envelope without adding stream reconstruction logic.

Use the framer when you need:

- **Protocol integration**: You already manage read and write boundaries elsewhere.
- **Debugging**: You want to inspect the actual encoded HTTY output.
- **Custom transport composition**: You are building your own byte-stream wrapper.

~~~ ruby
require "stringio"
require "protocol/htty"

output = StringIO.new
framer = Protocol::HTTY::Framer.new(StringIO.new, output)

framer.write_chunk("hello")
framer.flush

output.string
# => "\ePHTTY;1;aGVsbG8=\e\\"
~~~

### Streaming Opaque Bytes

If you want HTTY to behave like a normal byte stream, use {ruby Protocol::HTTY::Stream}. It splits outgoing data into HTTY chunks, flushes them through the underlying transport, and reconstructs the original bytes on read.

This is the right level when you need:

- **HTTP/2 transport bridging**: Feed an `h2c` connection through terminal-safe framing.
- **Chunk reconstruction**: Ignore HTTY chunk boundaries and work with plain bytes.
- **Simple integration**: Read and write data without manually handling base64 envelopes.

~~~ ruby
require "stringio"
require "protocol/htty"

transport = StringIO.new
writer = Protocol::HTTY::Stream.new(StringIO.new, transport)

writer.write("hello world")
writer.close

transport.rewind

reader = Protocol::HTTY::Stream.new(transport, StringIO.new)

reader.read(11)
# => "hello world"

reader.read
# => nil
~~~

### Carrying an HTTP/2 Preface

HTTY does not interpret HTTP/2 frames. It only preserves byte ordering while moving the connection through terminal-safe chunks. That makes it suitable for forwarding the client connection preface and subsequent frame exchange unchanged.

~~~ ruby
require "stringio"
require "protocol/http2"
require "protocol/htty"

transport = StringIO.new
stream = Protocol::HTTY::Stream.new(StringIO.new, transport)

stream.write(Protocol::HTTP2::CONNECTION_PREFACE)
stream.close

transport.rewind

reader = Protocol::HTTY::Stream.new(transport, StringIO.new)
preface = reader.read(Protocol::HTTP2::CONNECTION_PREFACE.bytesize)

puts preface == Protocol::HTTP2::CONNECTION_PREFACE
# => true
~~~

## Best Practices

- Use {ruby Protocol::HTTY::Stream} unless you specifically need direct control over HTTY chunk boundaries.
- Keep HTTY responsible only for framing and byte transport. Let HTTP/2 express readiness, stream lifecycle, and shutdown.
- Close or flush writers when you need encoded chunks to become visible to the underlying transport immediately.
- Treat HTTY as a transport shim, not an application protocol.

## Common Pitfalls

- Do not assign semantic meaning to HTTY chunk boundaries. Receivers must reconstruct a continuous byte stream.
- Do not mix raw HTTP/2 bytes with HTTY framing on the same transport direction after framing has started.
- Do not add request or rendering semantics at the HTTY layer. Those belong to higher-level systems built on top of the reconstructed HTTP/2 connection.

## Next Steps

For the on-wire format, versioning rules, and sender/receiver requirements, see the [Specification](../specification/readme).