# Releases

## v0.3.0

  - Change `Protocol::HTTY::Stream` to take explicit input and output endpoints using `Stream.new(input, output)` and `Stream.open(input, output, **options)`.
  - Read HTTY input without buffering ahead, preserving HTTP/2 frame boundaries by reading only the announced frame payload length.

## v0.2.0

  - Add `Protocol::HTTY::Stream.open(stream, **options)` as the preferred constructor for bootstrapping HTTY over an existing stream.
  - Inline HTTY bootstrap encoding and decoding into `Protocol::HTTY::Stream`, keeping the public API focused on the single raw byte-stream abstraction used by HTTP/2.

## v0.1.0

  - Initial release.
