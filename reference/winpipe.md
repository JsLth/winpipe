# Named pipes

Functions to create, open, and close named pipes on Windows.

- `winpipe()` creates a new named pipe on Windows.

- `is_winpipe()` checks if an object is a winpipe.

- `np_listen()` blocks the session and listens to a pipe.

- `np_disconnect()` disconnects a client.

- `np_exists()` checks if a named pipe name exists.

- `np_list()` lists all named pipes currently on the machine.

## Usage

``` r
winpipe(
  name,
  open = "r+",
  server = !np_exists(name),
  blocking = FALSE,
  sddl = sd_default(),
  max_instances = Inf,
  timeout = getOption("timeout")
)

# S3 method for class 'winpipe'
open(con, open = "r+", blocking = FALSE, ...)

is_winpipe(x)

np_listen(con)

np_disconnect(con)

np_exists(name)

np_list()
```

## Arguments

- name:

  `[character(1)]`

  Pipe name, with or without the `\\.\pipe\` prefix.

- open:

  `[character(1)]`

  A description of how to open the connection. See
  [`pipe`](https://rdrr.io/r/base/connections.html).

- server:

  `[logical(1)]`

  Whether the connection should be opened as a server or client. If
  `TRUE`, creates the pipe. If `FALSE`, only connects to it. Defaults to
  `TRUE` when no pipe with that can be found, otherwise `FALSE`.

- blocking:

  `[logical(1)]`

  Whether the connection is blocking. See
  [`open`](https://rdrr.io/r/base/connections.html). For a server, a
  blocking open waits until a client connects (see `timeout`). A
  non-blocking open returns immediately and `np_listen()` can accept a
  client later. For reads, a blocking connection waits for data, while a
  non-blocking one returns only what is available (possibly nothing) and
  leaves a partial line for the next read. Writes always block. Defaults
  to `FALSE`.

- sddl:

  `[winpipe_sd]` or `[character(1)]`

  Security descriptor string, or a security descriptor built with
  [`sd_create`](https://jslth.github.io/winpipe/reference/security_descriptor.md).
  Ignored if `server` is `FALSE`. Defaults to the default DACL of the
  current token
  ([`sd_default`](https://jslth.github.io/winpipe/reference/security_descriptor.md)).

- max_instances:

  `[numeric(1)]`

  Maximum allowed instances that can be opened on a named pipe. Can be a
  number between 1 and 254. If `Inf`, a maximum of 255 instances is
  allowed. `max_instances` is set on the creation of the pipe. This
  means that all connections connecting to an existing pipe cannot
  change the maximum number of instances. Defaults to `Inf`.

- timeout:

  `[numeric(1)]`

  Seconds without progress before a read, write, accept, or open fails
  with an error. If `Inf`, waits forever. Defaults to
  `getOption("timeout")`. A read that times out after receiving bytes
  returns them with a warning instead of discarding them.

- con:

  `[winpipe]`

  A `winpipe` connection created by `winpipe`.

- ...:

  Further arguments passed to
  [`open`](https://rdrr.io/r/base/connections.html).

- x:

  Any object.

## Value

`named_pipe` returns a connection of class `"named_pipe"`. All methods
accepting a connection work on named pipes. Use `open = "r+b"` for
[`readBin`](https://rdrr.io/r/base/readBin.html) and
[`writeBin`](https://rdrr.io/r/base/readBin.html).

## Details

Named pipes behave differently depending on whether they are initialized
as a server or client. When `server = TRUE`,
[`open()`](https://rdrr.io/r/base/connections.html) creates the named
pipe so that a client can connect to it. With `blocking = TRUE` the open
waits for a client to connect; otherwise run `np_listen()` to block the
session until one does. `np_disconnect()` drops the current client and
discards all unread data.
[`close()`](https://rdrr.io/r/base/connections.html) destroys the
instance but does not disconnect first, so data already written stays
readable by the client.

When `server = FALSE`, the named pipe cannot be created or destroyed.
Clients can only read or write but not change the state of the named
pipe. If a client named pipe is opened but there is no server instance
available to answer it, it will block the session until its timeout is
reached or an interrupt is signaled.

## Blocking

The principles of blocking are explained in
[`pipe`](https://rdrr.io/r/base/connections.html). Since
[`readLines()`](https://rdrr.io/r/base/readLines.html) with `n = -1`
reads until the end of the input, reading all lines from a server blocks
the session until the client signals the end of the input by closing the
connection.

## Examples

``` r
server <- winpipe("test")
client <- winpipe("test", server = FALSE)

# Nothing written yet
readLines(server)
#> character(0)

# Client writes to pipe
cat("hello", file = client)
writeLines("world")
#> world

# Server can now receive the content
readLines(server)
#> character(0)

close(client)
close(server)
```
