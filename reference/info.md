# Low-level information about a named pipe

Functions to retrieve low-level information about a named pipe.

- `np_config()` returns the pipe configuration.

- `np_state()` returns the current clients.

- `np_peek()` looks at the bytes of a pipe without reading.

- `np_connected()` checks if a client or server is connected to the
  other side of the pipe.

- `np_sd()` returns the [security
  descriptor](https://jslth.github.io/winpipe/reference/security_descriptor.md).

## Usage

``` r
np_config(con)

np_state(con)

np_peek(con, warn = TRUE)

np_connected(con)

np_sd(con)
```

## Arguments

- con:

  `[winpipe]`.

  An open `winpipe` as created by
  [`winpipe`](https://jslth.github.io/winpipe/reference/winpipe.md).

- warn:

  `[logical(1)]`

  Whether to warn if a pipe cannot be peeked from. `np_peek()` will run
  without error even if a pipe can technically not be read from because
  it is not connected to anything. In this case, it signals a warning
  and returns 0. Set to `TRUE` if reading from a disconnected pipe is
  intended.

## Value

`np_config()` returns:

- `is_server` and `is_client`: Whether the pipe is started as a server
  or client.

- `is_message_type` and `is_byte_type`: Whether the pipe reads data as
  bytes or messages. Pipes created using `winpipe` always read bytes.

- `out_buffer_size` and `in_buffer_size`: Size of input and output
  chunks.

- `max_instances`: Maximum allowed instances.

`np_state()` returns:

- `state`: The reading mode of the pipe. Can be either blocking or
  non-blocking and byte-mode or message-mode. Pipes created using
  `winpipe` should always be in blocking byte-mode.

- `current_instances`: Number of instances related to a pipe.

- `username`: If `con` is a server, reports the username of the current
  client, if any. If `con` is a client, `NA`.

`np_peek()` returns the number of bytes available to read from the pipe.
If `np_peek()` cannot read from the pipe, returns the error code as a
warning.

`np_connected()` returns `TRUE` when `con` is a server and a client is
connected or when `con` is a client and a server is connected. If the
other side is not connected, returns `FALSE`.

`np_sd()` returns an object of class
[`winpipe_sd`](https://jslth.github.io/winpipe/reference/security_descriptor.md).

## Examples

``` r
srv <- winpipe("test")
cli <- winpipe("test")

# client has a server, so np_connected() is TRUE
np_connected(cli)
#> [1] TRUE

np_config(srv)
#> $is_server
#> [1] TRUE
#> 
#> $is_client
#> [1] FALSE
#> 
#> $is_message_type
#> [1] FALSE
#> 
#> $is_byte_type
#> [1] TRUE
#> 
#> $out_buffer_size
#> [1] 1048576
#> 
#> $in_buffer_size
#> [1] 1048576
#> 
#> $max_instances
#> [1] 255
#> 
np_state(srv)
#> $state
#> [1] "blocking byte-mode"
#> 
#> $current_instances
#> [1] 1
#> 
#> $username
#> [1] "runneradmin"
#> 

# Peek can track how many bytes are consumed from reading
np_peek(srv)
#> [1] 0
writeLines("hello\nworld", cli)
np_peek(srv)
#> [1] 12
readLines(srv, n = 1)
#> [1] "hello"
np_peek(srv)
#> [1] 6

np_sd(srv)
#> <winpipe_sd>
#> O:BAG:S-1-5-21-3776380004-1005456608-3524014338-513D:(A;;FA;;;BA)(A;;FA;;;SY)(A;;0x1200a9;;;S-1-5-5-0-872493)

close(srv)

# server closed, so client is serverless
np_connected(cli)
#> [1] FALSE

# peeking is still possible, but signals a warning
np_peek(cli)
#> Warning: The pipe has been ended. (error 109)
#> [1] 0

close(cli)
```
