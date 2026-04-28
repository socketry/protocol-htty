From terminal POV:

1. Start shell (e.g. fish).
2. Send "ruby server.rb" to start server.
3. Scan PTY output for bootstrap DCS sequence. Bytes before the sequence are
   discarded; bytes after it are retained in the scan buffer for the H2C framer.

4. Exchange H2C connection prefaces, make requests.

5. Send GOAWAY once done.

6. Tear down the H2C framer but NOT the underlying PTY IO. The scan buffer
   (internal to the PTY stream wrapper) survives so no bytes are lost at the
   session boundary.
6a. Go back to step 3.

From server side (loops for each session):

1. Set raw mode FIRST so the line discipline cannot mangle H2C bytes that
   arrive immediately after the client sees the bootstrap.
2. Send bootstrap sequence.
3. Scan stdin for the H2C connection preface (magic + SETTINGS). Bytes before
   the preface are discarded; bytes after are retained in the stdin buffer.
   Yes, connection preface is required — it lets us reuse standard H2 libraries.
4. Serve requests. After sending a response with END_STREAM, break the read
   loop immediately — do not wait for the client's GOAWAY (client is already
   scanning for the next bootstrap, so waiting would deadlock).
5. Send GOAWAY. Close the framer but NOT the underlying stdin/stdout.
5a. Clear raw mode.
5b. Go back to step 1.
