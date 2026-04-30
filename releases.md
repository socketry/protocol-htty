# Releases

## v0.2.0

  - Add `Protocol::HTTY::Stream.open(stream, **options)` as the preferred constructor for bootstrapping HTTY over an existing stream.
  - Inline HTTY bootstrap encoding and decoding into `Protocol::HTTY::Stream`, keeping the public API focused on the single raw byte-stream abstraction used by HTTP/2.

## v0.1.0

  - Initial release.
