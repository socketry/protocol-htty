# Releases

## v0.4.0

  - **Breaking**: Drop the `io-stream` dependency. `Stream.new` and `Stream.open` no longer coerce or wrap their `input` and `output` arguments; raw IO objects are used as-is. Callers that relied on `stream.io` returning an `IO::Stream::Buffered` should wrap the IO themselves before passing it in.
  - Simplify `Stream#read` to delegate directly to the underlying input, since the HTTP/2 framer always requests exact byte counts (header size, then payload length).

## v0.3.0

  - Change `Protocol::HTTY::Stream` to take explicit input and output endpoints using `Stream.new(input, output)` and `Stream.open(input, output, **options)`.
  - Read HTTY input without buffering ahead, preserving HTTP/2 frame boundaries by reading only the announced frame payload length.

## v0.2.0

  - Add `Protocol::HTTY::Stream.open(stream, **options)` as the preferred constructor for bootstrapping HTTY over an existing stream.
  - Inline HTTY bootstrap encoding and decoding into `Protocol::HTTY::Stream`, keeping the public API focused on the single raw byte-stream abstraction used by HTTP/2.

## v0.1.0

  - Initial release.
