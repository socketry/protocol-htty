# Getting Started

This guide explains how to get started with `protocol-htty` for DCS-bootstrapped raw HTTP/2 byte stream transport.

## Installation

Add the gem to your project:

~~~ bash
$ bundle add protocol-htty
~~~

## Why HTTY Exists

When you need to carry an `h2c` connection over stdin/stdout, PTYs, or SSH sessions, raw HTTP/2 bytes are not safe to write directly into a terminal that is still operating in ordinary text mode. HTTY solves that by emitting one terminal-safe bootstrap sequence and then handing the session over to raw byte transport.

Use `protocol-htty` when you need:

- **Terminal-safe takeover**: Start HTTY without rendering the transition as visible terminal text.
- **Raw byte transport**: Carry HTTP/2 bytes directly once takeover has happened.
- **Cross-runtime interoperability**: Keep the bootstrap small enough to reimplement in other languages or environments.

Without HTTY, higher-level systems would need to invent their own ad hoc terminal bootstrap and raw-mode coordination before they could safely carry HTTP/2 over terminal I/O.

## Core Concepts

- {ruby Protocol::HTTY::Stream} writes and reads the HTTY bootstrap sequence, then exposes the raw byte stream used after bootstrap.
- HTTY transports bytes only. HTTP/2 connection setup, stream lifecycle, and shutdown semantics remain owned by HTTP/2.

## Usage

The low-level API is intentionally small. Use {ruby Protocol::HTTY::Stream} to perform the bootstrap step and then carry raw bytes.

### Writing The Bootstrap

If you are integrating HTTY into an existing transport, create a stream wrapper around your byte-oriented IO. This gives you direct access to the terminal-safe bootstrap without adding any higher-level protocol policy.

Use explicit bootstrap calls when you need:

- **Protocol integration**: You already manage stream ownership elsewhere.
- **Debugging**: You want to inspect the actual bootstrap bytes.
- **Custom transport composition**: You are building your own raw byte-stream wrapper.

~~~ ruby
require "stringio"
require "io/stream"
require "protocol/htty"

output = StringIO.new
stream = IO::Stream::Duplex(StringIO.new, output)
htty = Protocol::HTTY::Stream.new(stream)

htty.write_bootstrap

output.string
# => "\eP+Hraw\e\\"
~~~

### Bootstrapping A Raw Stream

If you want HTTY to behave like a normal byte stream, use {ruby Protocol::HTTY::Stream}. It can emit the bootstrap for you, or consume it on the receiving side, and then expose the carried bytes directly.

This is the right level when you need:

- **HTTP/2 transport bridging**: Feed an `h2c` connection through HTTY without defining another message layer.
- **Bootstrap handling**: Keep the raw-mode transition in one place.
- **Simple integration**: Read and write bytes without manually parsing terminal control data.

~~~ ruby
require "stringio"
require "io/stream"
require "protocol/htty"

transport = StringIO.new
writer = Protocol::HTTY::Stream.open(IO::Stream::Duplex(StringIO.new, transport), bootstrap: :write)

writer.write("hello world")
writer.flush

transport.rewind

reader = Protocol::HTTY::Stream.open(IO::Stream::Duplex(transport, StringIO.new), bootstrap: :read)

reader.read(11)
# => "hello world"
~~~

### Carrying an HTTP/2 Preface

HTTY does not interpret HTTP/2 frames. It only performs the bootstrap and then preserves byte ordering while the connection runs over the raw transport. That makes it suitable for forwarding the client connection preface and subsequent frame exchange unchanged.

~~~ ruby
require "stringio"
require "io/stream"
require "protocol/http2"
require "protocol/htty"

transport = StringIO.new
stream = Protocol::HTTY::Stream.open(IO::Stream::Duplex(StringIO.new, transport), bootstrap: :write)

stream.write(Protocol::HTTP2::CONNECTION_PREFACE)
stream.flush

transport.rewind

reader = Protocol::HTTY::Stream.open(IO::Stream::Duplex(transport, StringIO.new), bootstrap: :read)
preface = reader.read(Protocol::HTTP2::CONNECTION_PREFACE.bytesize)

puts preface == Protocol::HTTP2::CONNECTION_PREFACE
# => true
~~~
