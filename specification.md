# HTTY Specification

This document specifies HTTY as a terminal-safe framing layer for carrying a plaintext HTTP/2 (`h2c`) byte stream over terminal side channels.

HTTY does not define a separate session protocol. Connection establishment, readiness, multiplexing, end-of-stream, reset, and shutdown semantics are all provided by HTTP/2 itself.

## Conventions

The key words `MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`, and `MAY` in this document are to be interpreted as normative requirement levels.

## Goals

HTTY is designed to provide the following properties:

1. It can carry an `h2c` byte stream over terminal stdin/stdout without rendering control data as visible terminal text.
2. It can transport arbitrary HTTP/2 bytes using a terminal-safe encoding.
3. It can be implemented consistently across different runtimes.
4. It can operate over PTYs and SSH sessions without auxiliary sockets or shared filesystems.
5. It adds as little additional protocol state as possible beyond terminal-safe framing.

## Non-Goals

HTTY does not define:

- HTML rendering.
- Browser embedding.
- Resource stores.
- Request routing.
- Form or click events.
- JavaScript execution.
- Inline scrollback placement.
- A filesystem mapping.
- A higher-level application model beyond HTTP/2 byte transport.

Those concerns belong either to HTTP/2 itself or to higher-level systems built on top of HTTY.

## Transport Model

An HTTY session carries one bidirectional HTTP/2 connection over the terminal's standard input and standard output streams.

Each direction of transport carries its own ordered byte stream:

- Standard output carries HTTY-framed bytes from the command toward the terminal.
- Standard input carries HTTY-framed bytes from the terminal toward the command.

Taken together, those two ordered byte streams MUST be interpreted as one plaintext HTTP/2 connection.

The first meaningful bytes sent by the HTTP/2 client on a new session MUST therefore be the HTTP/2 client connection preface, followed by the normal HTTP/2 frame exchange.

HTTY itself is responsible only for:

1. Embedding byte chunks within terminal-safe escape sequences.
2. Removing those escape sequences from visible terminal output.
3. Decoding the chunk payload.
4. Reconstructing the original ordered byte stream.

All connection and stream semantics above that layer are owned by HTTP/2.

## Framing

Each HTTY chunk MUST be encoded as a DCS sequence of the following form:

``` text
ESC P HTTY;1;BASE64_CHUNK ESC \
```

Where:

- `ESC` is byte `0x1b`.
- `P` begins a DCS sequence.
- `HTTY` is the protocol identifier.
- `1` is the protocol version.
- `BASE64_CHUNK` is a strict base64 encoding of a consecutive byte slice from the underlying HTTP/2 stream.
- `ESC \` terminates the DCS sequence.

Chunks MUST be base64-encoded.

### Rationale for Base64

HTTP/2 frames are arbitrary binary and may contain bytes that would otherwise terminate or corrupt terminal escape parsing if sent directly inside a DCS envelope.

Base64 is required to ensure that HTTY payloads remain terminal-safe while keeping the framing layer simple and easy to reimplement.

### Example

A chunk carrying `hello` is encoded as:

``` text
ESC P HTTY;1;aGVsbG8= ESC \
```

## Stream Reconstruction

Senders MAY split either directional HTTP/2 byte stream across any number of HTTY chunks.

Receivers MUST reconstruct the original byte stream for each transport direction by concatenating decoded chunk payloads in order.

HTTY chunk boundaries have no semantic meaning above the framing layer.

In particular:

- An HTTP/2 frame may span multiple HTTY chunks.
- Multiple HTTP/2 frames may appear within one HTTY chunk.
- The receiver MUST NOT assign any higher-level meaning to chunk boundaries.

## Transport Lifecycle

HTTY does not define transport-level open or close packets.

Instead, HTTY maps terminal transport events onto the lifecycle of the carried HTTP/2 connection:

- Use of HTTY framing on a given transport direction is implied by the appearance of the first valid HTTY chunk on that direction.
- Both transport directions of a single HTTY session MUST use the same HTTY framing version.
- HTTP/2 readiness MUST be expressed by the normal connection preface and `SETTINGS` exchange.
- HTTP/2 stream lifecycle MUST be expressed by standard HTTP/2 frame and flag semantics.
- Graceful connection shutdown SHOULD be expressed by HTTP/2 mechanisms such as `GOAWAY`.
- Abrupt termination MUST be expressed by terminal or PTY EOF.

If the underlying command exits or the terminal stream closes unexpectedly, the carried HTTP/2 connection MUST be considered aborted.

## Environment Discovery

An implementation MAY advertise HTTY support to child processes using the `HTTY` environment variable.

`HTTY` specifies the maximum supported HTTY framing version exposed by the current terminal environment.

The variable is interpreted as follows:

- If `HTTY` is absent, HTTY support is not advertised.
- If `HTTY=0`, HTTY is explicitly unsupported or disabled.
- If `HTTY` is a positive integer, that value is the maximum supported HTTY framing version.
- If `HTTY` is present but not a valid non-negative integer, it MUST be treated as unsupported.

Senders SHOULD treat `HTTY` as an out-of-band capability advertisement, not as the sole protocol negotiation mechanism.

In particular:

- The on-wire HTTY framing MUST still include the concrete version in use.
- A sender SHOULD choose a version no greater than both the advertised `HTTY` value and the highest version it implements.
- If no supported version is available, the sender MUST NOT emit HTTY framing.

This mechanism allows a terminal or intermediate environment to explicitly disable HTTY while preserving forward compatibility for future framing versions.

## Sender Requirements

Senders MUST:

1. Encode each chunk using strict base64.
2. Emit chunks using the exact DCS envelope defined above.
3. Preserve chunk ordering.
4. Preserve the byte order of the carried HTTP/2 stream.
5. Stop emitting HTTY chunks once the underlying transport has ended.
6. Once HTTY framing has started on a transport direction, convey all bytes of the carried HTTP/2 stream on that direction inside HTTY chunks.
7. Once HTTY framing has started on a transport direction, senders MUST NOT emit any bytes belonging to the carried HTTP/2 stream on that direction as raw terminal output.

Senders MAY:

- Choose any chunk size.
- Split large HTTP/2 writes across multiple chunks.
- Coalesce adjacent writes into a single chunk.

## Receiver Requirements

Receivers MUST:

1. Detect HTTY chunks embedded within terminal output.
2. Ignore non-HTTY terminal bytes until a valid HTTY prefix is found.
3. Reject unsupported HTTY versions.
4. Reject malformed HTTY chunks.
5. Decode chunk payloads using strict base64.
6. Reconstruct the original ordered HTTP/2 byte stream for each transport direction.
7. Avoid rendering HTTY control data as visible terminal text.

Receivers SHOULD:

- Discard incomplete chunks.
- Resume normal terminal processing after malformed or truncated input when practical.
- Bound chunk size and total buffered data to avoid unbounded memory growth.

## Error Handling

Receivers MUST treat the following conditions as HTTY framing errors:

- An HTTY chunk using an unsupported version.
- A malformed HTTY envelope.
- A payload that is not valid strict base64.

Receivers MUST treat the following as truncation rather than a valid chunk:

- End-of-input before the terminating `ESC \` sequence.

Once HTTY framing has started on a transport direction, malformed or truncated HTTY framing on that direction MUST cause the corresponding carried HTTP/2 connection to be considered aborted.

Malformed HTTY framing invalidates only the framing layer. Higher-level HTTP/2 state MUST NOT be inferred from malformed chunks that could not be decoded into bytes.

## Terminal Compatibility

HTTY is designed for transport over TTY-compatible byte streams.

Compatibility requirements:

- It MUST work over stdin/stdout.
- It SHOULD work over SSH because it does not depend on local sockets or shared filesystems.
- It MUST NOT require raw binary framing outside terminal-safe escape sequences.

HTTY does not require:

- Localhost networking.
- Side channels such as Unix sockets.
- Shared storage between sender and receiver.

## Security Considerations

HTTY itself only defines framing and byte transport. Its main safety property is that arbitrary HTTP/2 bytes are encoded into terminal-safe payloads before being embedded in the terminal stream.

Implementations SHOULD still consider:

- Avoiding terminal corruption when chunks are malformed.
- Rejecting unsupported protocol versions.
- Bounding buffer growth and chunk sizes.
- Preventing malformed framing data from leaking into visible terminal output.

Security policies for HTML, requests, rendering, resource access, and user interaction are outside the scope of HTTY and must be defined by higher-level consumers.

## Relationship to HTTP/2

HTTY is not an application protocol parallel to HTTP/2.

Instead, HTTY is a transport shim that allows an `h2c` connection to pass through terminal-oriented byte streams safely.

That means:

- HTTY does not replace HTTP/2 frame semantics.
- HTTY does not add another stream lifecycle model.
- HTTY does not redefine requests, responses, events, or resources.
- HTTY exists only to preserve the integrity of the carried `h2c` byte stream across terminal infrastructure.

## Relationship to Higher-Level Systems

Higher-level systems can build directly on top of the reconstructed HTTP/2 connection.

Those systems define request semantics, rendering, resource handling, and user interaction. HTTY does not.

## Implementation Notes

Implementations that currently expose packet-oriented helpers should converge on chunk framing and byte-stream reconstruction without transport-level control packets.

The core design goal remains the same: the framing layer should stay small enough to be reimplemented consistently without introducing a second application protocol beside HTTP/2.