# HTTY Specification

This document specifies HTTY as a DCS-bootstrapped raw-mode takeover transport for carrying a plaintext HTTP/2 (`h2c`) connection over terminal-attached sessions.

HTTY does not define a second application protocol beside HTTP/2. Once HTTY is active, connection establishment, readiness, multiplexing, end-of-stream, reset, and graceful shutdown semantics are all provided by HTTP/2 itself.

## Conventions

The key words `MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`, and `MAY` in this document are to be interpreted as normative requirement levels.

## Goals

HTTY is designed to provide the following properties:

1. It can carry an `h2c` connection over terminal stdin/stdout, PTYs, and SSH sessions.
2. It can switch a terminal-attached session into a mode where HTTP/2 bytes are transported directly without terminal-oriented interpretation.
3. It can be implemented consistently across different runtimes.
4. It can operate without auxiliary sockets or shared filesystems.
5. It adds as little protocol state as possible beyond the decision to enter HTTY mode.

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
- A second lifecycle model parallel to HTTP/2.

Those concerns belong either to HTTP/2 itself or to higher-level systems built on top of HTTY.

## Transport Model

An HTTY session carries one bidirectional HTTP/2 connection over the terminal's standard input and standard output streams.

Before HTTY takes over, the surrounding terminal session MAY still be operating in ordinary terminal mode. HTTY support discovery and advertisement are specified by this document via the `HTTY` environment variable. HTTY v1 defines one interoperable bootstrap sequence for entering takeover mode.

Once HTTY takes over a session:

- the surrounding terminal or PTY MUST be placed into raw mode or an equivalent byte-preserving mode,
- HTTY MUST have exclusive ownership of the session byte stream,
- bytes on standard input and standard output MUST be interpreted only as the two directions of one plaintext HTTP/2 connection.

In particular:

- standard input carries bytes from the terminal side toward the command,
- standard output carries bytes from the command toward the terminal side,
- together those two ordered byte streams MUST be interpreted as one plaintext HTTP/2 connection.

The first meaningful bytes sent by the HTTP/2 client after takeover MUST therefore be the HTTP/2 client connection preface, followed by the normal HTTP/2 frame exchange.

HTTY itself is responsible only for establishing this byte-stream takeover model. All connection and stream semantics above that layer are owned by HTTP/2.

## Bootstrap And Takeover

HTTY v1 defines a terminal-directed bootstrap sequence which precedes raw takeover:

~~~ text
ESC P + H raw ESC \
~~~

Equivalently, using C-style escapes:

~~~ text
\u001bP+Hraw\u001b\\
~~~

This bootstrap is a DCS sequence with:

- intermediate byte `+`,
- final byte `H`,
- payload `raw`.

The bootstrap sequence is emitted on the command-to-terminal direction before HTTP/2 bytes begin flowing. It is terminal control data, not part of the carried HTTP/2 connection.

HTTY v1 only defines the `+H` DCS sequence with payload `raw`. Other terminal control sequences, including implementation-specific DCS markers used by a session owner before takeover or after recovery, are outside the HTTY v1 wire protocol and MUST NOT be interpreted as HTTY lifecycle messages.

An HTTY v1 receiver that supports takeover MUST:

1. recognize this bootstrap sequence on the terminal-facing output stream,
2. consume it without rendering it as ordinary terminal output,
3. switch the session into raw or equivalent byte-preserving mode,
4. treat subsequent bytes on standard input and standard output as the two directions of one plaintext HTTP/2 connection.

After the bootstrap has been accepted, HTTY is defined around the following takeover boundary:

1. A higher-level session owner decides that HTTY should begin.
2. The command side switches its own stdin to raw or byte-preserving mode.
3. The command side emits the HTTY bootstrap sequence.
4. The terminal-facing side consumes the bootstrap and switches the terminal-attached transport into raw mode.
5. From that point until termination, the transport carries plain `h2c` bytes.

Implementations MAY still use environment discovery, process setup, terminal integration, or other out-of-band coordination to decide whether HTTY should begin. However, once HTTY v1 takeover is initiated in-band, the bootstrap sequence above is the interoperable mechanism by which the command side signals the transition to raw transport.

The important interoperability rule is that once HTTY has taken over a session, the peers MUST speak plain `h2c` over the raw byte stream until the session ends.

### Command-Side Ordering

On the command side, raw or byte-preserving mode MUST be activated on stdin BEFORE the bootstrap sequence is emitted. The terminal-facing side may transmit the HTTP/2 connection preface immediately upon receiving the bootstrap; if raw mode is not yet active when those bytes arrive, the line discipline may corrupt them.

The required ordering is:

1. Activate raw mode on stdin.
2. Emit the bootstrap sequence on stdout.
3. Scan incoming bytes for the HTTP/2 connection preface, discarding any bytes that precede it.
4. Pass the connection preface and all subsequent bytes to the HTTP/2 implementation.

Bytes that arrive before the HTTP/2 connection preface MUST be discarded rather than forwarded. They may include terminal noise, echoed command text, or residual bytes from a prior session.

## Framing

HTTY adds one bootstrap sequence before takeover and no framing after takeover.

Once raw mode is active, the transport payload is simply the carried HTTP/2 byte stream itself.

In particular:

- The bootstrap sequence above is the only HTTY-defined control envelope in v1.
- HTTP/2 frame boundaries remain defined only by HTTP/2.
- HTTY MUST NOT add another message boundary layer above the raw byte stream.
- Receivers MUST pass the bytes through to the HTTP/2 implementation in order.

## Transport Lifecycle

HTTY does not define transport-level open or close packets.

Instead, lifecycle is mapped directly onto the surrounding terminal session and the carried HTTP/2 connection:

- HTTP/2 readiness MUST be expressed by the normal connection preface and `SETTINGS` exchange.
- HTTP/2 stream lifecycle MUST be expressed by standard HTTP/2 frame and flag semantics.
- Graceful connection shutdown SHOULD be expressed by HTTP/2 mechanisms such as `GOAWAY`.
- Abrupt termination MUST be expressed by terminal or PTY EOF, process exit, or equivalent transport loss.

For HTTY session lifecycle, the command-to-terminal direction is authoritative for graceful session completion. A terminal-facing HTTP/2 client MAY send `GOAWAY` at any time according to normal HTTP/2 semantics, but that does not by itself end the HTTY session or authorize the terminal-facing side to resume bootstrap scanning. A session is gracefully complete when the command side sends `GOAWAY`.

If the underlying command exits or the terminal-attached transport closes unexpectedly before command-side `GOAWAY`, the carried HTTP/2 connection MUST be considered aborted.

Closing a local HTTY stream abstraction does not by itself imply closing the surrounding PTY or terminal session. Session teardown remains a responsibility of the session owner.

### Session Resumption

A terminal-attached session MAY carry more than one HTTY session over its lifetime. After a session ends gracefully:

1. The command side sends `GOAWAY` to signal graceful shutdown of the HTTP/2 connection.
2. The command side SHOULD restore ordinary terminal mode (cooked mode or equivalent) on its stdin.
3. The terminal-facing side resumes scanning the byte stream for the next bootstrap sequence.
4. A new HTTY session begins when the command side emits a new bootstrap sequence, following the same ordering requirements as the first session.

For graceful session boundaries, implementations MUST preserve bytes buffered across session boundaries. Bytes read from the transport past the last frame of a completed session MUST remain available for the next bootstrap scan rather than being discarded.

Bytes that arrive at the terminal-facing side between the end of one session and the detection of the next bootstrap MUST NOT be forwarded to any HTTP/2 implementation. They may include `GOAWAY` frame bytes or other residual data from the prior session and MUST be treated as pre-bootstrap noise by the next scan.

Aborted sessions are a session-owner concern rather than an HTTY reset protocol. If the carried HTTP/2 connection fails, the command crashes, or the terminal byte stream becomes unsynchronized, the session owner MAY discard buffered bytes from the failed session, restore or nudge the surrounding shell or terminal state by local policy, and resume scanning for a fresh HTTY bootstrap. Any marker used to automate that recovery is implementation-specific terminal control data, not an HTTY v1 control envelope.

For example:

- if the client closes all tabs and no HTTY consumer remains, the session owner SHOULD terminate the terminal-emulator-to-command side of the session and SHOULD tear down the session as a whole,
- if the command exits, the session owner SHOULD treat the command-to-terminal side as finished and SHOULD terminate the session as a whole.

## Terminal Input

Once HTTY has taken over a session, ordinary terminal keystrokes are no longer a separate interactive protocol.

Implementations MUST NOT treat arbitrary terminal input as unrelated text traffic once the raw HTTY transport is active.

In practice, this means:

- session owners SHOULD stop forwarding unmanaged terminal keystrokes into the transport,
- any input that continues to reach the raw transport MUST be considered part of the carried HTTP/2 connection,
- implementations MAY reserve explicit detach or escape mechanisms, but such mechanisms are session-management features outside this wire specification.

## Environment Discovery

An implementation MAY advertise HTTY support to child processes using the `HTTY` environment variable.

This environment variable is the standard discovery and advertisement mechanism defined by HTTY v1. It allows a parent terminal environment to tell a child process whether HTTY is available and which transport version is supported.

`HTTY` specifies the maximum supported HTTY transport version exposed by the current terminal environment.

The variable is interpreted as follows:

- If `HTTY` is absent, HTTY support is not advertised.
- If `HTTY=0`, HTTY is explicitly unsupported or disabled.
- If `HTTY` is a positive integer, that value is the maximum supported HTTY transport version.
- If `HTTY` is present but not a valid non-negative integer, it MUST be treated as unsupported.

Senders SHOULD treat `HTTY` as an out-of-band capability advertisement, not as the sole protocol negotiation mechanism.

The `HTTY` environment variable does not, by itself, require takeover to begin. It advertises support and version bounds. The decision to request or initiate raw-mode takeover remains a session-management concern outside the wire protocol defined here.

This mechanism allows a terminal or intermediate environment to explicitly disable HTTY while preserving forward compatibility for future transport versions.

## Sender Requirements

Once HTTY has taken over a session, senders MUST:

1. Preserve byte ordering on each transport direction.
2. Preserve the byte order of the carried HTTP/2 connection exactly.
3. Stop emitting HTTY transport bytes once the underlying session transport has ended.
4. Avoid emitting unrelated terminal text on a transport direction that has been taken over by HTTY.

Senders MAY:

- buffer writes according to the needs of the underlying runtime,
- split writes arbitrarily, provided byte ordering is preserved,
- coalesce adjacent writes arbitrarily, provided byte ordering is preserved.

## Receiver Requirements

Once HTTY has taken over a session, receivers MUST:

1. Treat standard input and standard output as raw byte streams.
2. Preserve byte ordering on each transport direction.
3. Reconstruct the original HTTP/2 byte stream for each direction without assigning extra meaning to write boundaries.
4. Deliver those bytes to the HTTP/2 implementation unchanged.

Receivers SHOULD:

- bound buffered data to avoid unbounded memory growth,
- treat unexpected transport loss as connection abort.

## Error Handling

Before takeover, malformed or unsupported bootstrap data MUST NOT cause the receiver to enter HTTY mode. Such data MAY be ignored, logged, or treated as ordinary terminal output according to local policy.

Once HTTY is active, malformed data is not an HTTY framing error because HTTY no longer defines a framing envelope beyond the initial bootstrap. Unexpected bytes are simply malformed input to the carried HTTP/2 connection.

Accordingly:

- invalid bytes or invalid structure after takeover MUST be handled as HTTP/2 protocol errors,
- terminal or PTY EOF before graceful HTTP/2 shutdown MUST be treated as connection abort,
- implementations MUST NOT infer higher-level HTTP/2 state from an abruptly terminated transport beyond what HTTP/2 itself defines.

## Terminal Compatibility

HTTY is designed for transport over terminal-attached byte streams.

Compatibility requirements:

- It MUST work over stdin/stdout once those streams have been placed into a raw byte-preserving mode.
- It SHOULD work over SSH and PTYs provided the session owner can switch the connection into raw mode.
- It MUST NOT require auxiliary localhost networking or shared filesystem state.

HTTY does not require:

- Localhost networking.
- Side channels such as Unix sockets.
- Shared storage between sender and receiver.

## Security Considerations

HTTY itself only defines takeover into a raw byte transport for HTTP/2. The main safety concern is therefore session ownership: once takeover occurs, arbitrary bytes on the transport are interpreted as part of the carried HTTP/2 connection.

Implementations SHOULD consider:

- preventing unmanaged terminal keystrokes from being injected into the active HTTY transport,
- making detach and teardown behavior explicit at the session-owner layer,
- bounding buffer growth,
- treating unexpected transport loss as abort.

Security policies for HTML, requests, rendering, resource access, and user interaction are outside the scope of HTTY and must be defined by higher-level consumers.

## Relationship to HTTP/2

HTTY is not an application protocol parallel to HTTP/2.

Instead, HTTY is a transport takeover convention that allows an `h2c` connection to own a raw terminal-attached byte stream.

That means:

- HTTY does not replace HTTP/2 frame semantics.
- HTTY does not add another stream lifecycle model.
- HTTY does not redefine requests, responses, events, or resources.
- HTTY exists only to give HTTP/2 exclusive ownership of a terminal-attached byte stream.

## Relationship to Higher-Level Systems

Higher-level systems can build directly on top of the resulting HTTP/2 connection.

Those systems define request semantics, rendering, resource handling, browser behavior, and user interaction. HTTY does not.

## Implementation Notes

Implementations that currently expose chunk-oriented or packet-oriented helpers should converge on the simpler raw-byte transport model described here.

Implementations that expose stream-like wrappers MAY model `close` as local write shutdown only, provided this does not implicitly close any broader session transport.

The core design goal remains the same: HTTY should stay small enough to be reimplemented consistently without introducing a second application protocol beside HTTP/2.
