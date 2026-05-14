# HTTY PTY Example Design

These examples demonstrate HTTY over a real PTY using `protocol-htty` and `protocol-http2`.

## Server side (`server.rb`)

Runs one HTTY session then exits so the shell can return to its prompt.

1. Set raw mode FIRST so the line discipline cannot mangle H2C bytes that
   arrive immediately after the client sees the bootstrap.
2. Open a `Protocol::HTTY::Stream` with `bootstrap: :write`, which emits
   the bootstrap DCS sequence to stdout.
3. Pass the stream to `Protocol::HTTP2::Framer` and serve requests.
4. After sending a response with `END_STREAM`, break the read loop — do not
   wait for the client's GOAWAY (the client is already scanning for the next
   bootstrap, so waiting would deadlock).
5. Send GOAWAY. `Protocol::HTTY::Stream#close` does not close the underlying
   stdin/stdout, so the terminal remains open.

## Client side (`client.rb`)

Drives the shell in a PTY, repeating the session loop.

1. Spawn the shell in a PTY so the server sees a real TTY on stdin.
2. Write `ruby server.rb` to the shell.
3. Scan PTY output for the HTTY bootstrap DCS sequence using `PTYStream`.
   `PTYStream` is a chunk-buffered wrapper around the PTY master — it exists
   because `Protocol::HTTY::Stream` is designed for already-raw IO and reads
   one byte at a time. The client side needs chunk-based buffering plus the
   multi-session `reset!` dance.
4. Pass `PTYStream` to `Protocol::HTTP2::Framer` and make a GET request.
5. Send GOAWAY once the response is received. `PTYStream` is not closed, so
   its internal buffer survives into the next bootstrap scan.
6. Call `PTYStream#reset!` to resynchronize the shell before queuing the next
   session, then loop back to step 2.
