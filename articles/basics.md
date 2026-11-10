# Basics of winpipes

``` r

library(winpipe)
```

A named pipe (also called a FIFO for first-in, first-out) is a mechanism
for inter-process communication (IPC) that lets two unrelated processes
exchange data as if it were a file. Unlike a regular file, however, it
does not store data on disk. Whatever one process writes, the other
reads in order (first in, first out).

While the concept of a named pipe exists both on Linux and Windows,
named pipes on Windows have some important caveats that make
cross-platform R support for them traditionally weak. Windows named
pipes:

- are not part of the Windows file system but are reserved a special
  namespace (`\\.\pipe\*`).
- can be bidirectional, so both sides can read and write.
- have an explicit server/client API with support for multiple pipe
  instances.
- support access control through security descriptors.
- work over the network.
- support message streams.

Except for network access and message streams (which I think are mostly
useless for R applications), [winpipe](https://github.com/jslth/winpipe)
supports all of these features. For a comparison to existing named pipe
implementations, see
[`vignette("compare", package = "winpipe")`](https://jslth.github.io/winpipe/articles/compare.md).

## Server and client

You can create a named pipe with the function
[`winpipe()`](https://jslth.github.io/winpipe/reference/winpipe.md). As
mentioned earlier, named pipes on Windows can be both server and client.
Importantly, only a server can create a pipe while a client can only
connect to one.

``` r

np_exists("example-pipe")
#> [1] FALSE
cli <- winpipe("example-pipe", server = FALSE)
#> Error in `open.connection()`:
#> ! The system cannot find the file specified. (error 2)
```

``` r

srv <- winpipe("example-pipe", server = TRUE)
cli <- winpipe("example-pipe", server = FALSE)
```

A `winpipe` is a standard R connection, which means that reading and
writing works out of the box.

``` r

srv
#> A connection with                                       
#> description "\\\\.\\pipe\\example-pipe"
#> class       "winpipe"                  
#> mode        "r+"                       
#> text        "text"                     
#> opened      "opened"                   
#> can read    "yes"                      
#> can write   "yes"
```

``` r

writeLines("send me a dataset", cli)
readLines(srv)
#> [1] "send me a dataset"
```

This also means that all wrappers around base I/O work out of the box.

``` r

write.table(cars, srv)
head(read.table(cli))
#>   speed dist
#> 1     4    2
#> 2     4   10
#> 3     7    4
#> 4     7   22
#> 5     8   16
#> 6     9   10
```

Similar to I/O, connecting to a named pipe also follows a FIFO
principle. Since a named pipe allows multiple instances, one named pipe
can be served by multiple servers and listened to by multiple clients.
Right now, there is one server and one client. If we tried to connect
another client, it would fail because there is no free server available.

``` r

cli2 <- winpipe("example-pipe")
#> Error in `open.connection()`:
#> ! All pipe instances are busy. (error 231)
```

Instead, we need to create another server first, which is able to serve
another client.

``` r

srv2 <- winpipe("example-pipe", server = TRUE)
cli2 <- winpipe("example-pipe")
```

By doing this, we have created a second instance of the same pipe. You
can check the number of instances by inspecting the state of a pipe.

``` r

np_state(srv)
#> $state
#> [1] "blocking byte-mode"
#> 
#> $current_instances
#> [1] 2
#> 
#> $username
#> [1] "runneradmin"
```

If a server disconnects, the client loses its ability to communicate
through a pipe. The ability of a client to communicate to a named pipe
depends on the availability of a server.

``` r

np_connected(cli2)
#> [1] TRUE
close(srv2)
np_connected(cli2)
#> [1] FALSE
writeLines("hello?", cli2)
#> Error in `writeLines()`:
#> ! The pipe is being closed. (error 232)
```

``` r

close(cli2)
```

## Server privileges

Servers have some privileges when it comes to handling clients. First,
they are allowed to *impersonate* as a client. By impersonating, they
can retrieve information from the clients end. In
[winpipe](https://github.com/jslth/winpipe), this is supported through
[`np_token_info()`](https://jslth.github.io/winpipe/reference/np_whoami.md).

``` r

np_token_info(srv)
#> $user
#> [1] "S-1-5-21-3289802278-1561746829-1498425070-500"
#> 
#> $sid
#> [1] "S-1-5-21-3289802278-1561746829-1498425070-500"
#> 
#> $groups
#>                                             name
#> 1  S-1-5-21-3289802278-1561746829-1498425070-513
#> 2                                        S-1-1-0
#> 3                                      S-1-5-114
#> 4                                   S-1-5-32-544
#> 5                                   S-1-5-32-545
#> 6                                        S-1-5-4
#> 7                                        S-1-2-1
#> 8                                       S-1-5-11
#> 9                                       S-1-5-15
#> 10                                     S-1-5-113
#> 11                              S-1-5-5-0-771692
#> 12                                       S-1-2-0
#> 13                                   S-1-5-64-10
#> 14                                  S-1-16-12288
#>                                              sid enabled
#> 1  S-1-5-21-3289802278-1561746829-1498425070-513    TRUE
#> 2                                        S-1-1-0    TRUE
#> 3                                      S-1-5-114    TRUE
#> 4                                   S-1-5-32-544    TRUE
#> 5                                   S-1-5-32-545    TRUE
#> 6                                        S-1-5-4    TRUE
#> 7                                        S-1-2-1    TRUE
#> 8                                       S-1-5-11    TRUE
#> 9                                       S-1-5-15    TRUE
#> 10                                     S-1-5-113    TRUE
#> 11                              S-1-5-5-0-771692    TRUE
#> 12                                       S-1-2-0    TRUE
#> 13                                   S-1-5-64-10    TRUE
#> 14                                  S-1-16-12288   FALSE
#> 
#> $elevated
#> [1] TRUE
#> 
#> $integrity
#> [1] "high"
#> 
#> $token_type
#> [1] "impersonation"
#> 
#> $impersonation_level
#> [1] "identification"
```

The output contains information about the client’s name, SID, group
membership, and permissions. The field `impersonation_level` shows us,
to what degree the server can impersonate. In this case, client and
server are the same user so only identification is allowed.

Second, the server is allowed to disconnect a client without closing the
connection. This leaves the server in a disconnected state where it is
not able to accept new clients. The server needs to explicitly decide
when to listen again using
[`np_listen()`](https://jslth.github.io/winpipe/reference/winpipe.md).

``` r

# Disconnect client
np_connected(srv)
#> [1] TRUE
np_disconnect(srv)
np_connected(cli)
#> [1] FALSE
close(cli)

# Client cannot connect again immediately
cli <- winpipe("example-pipe", server = FALSE)
#> Error in `open.connection()`:
#> ! All pipe instances are busy. (error 231)

# Only if the server decides to listen again can a client connect
np_listen(srv, blocking = FALSE)
cli <- winpipe("example-pipe", server = FALSE)
```

``` r

close(srv)
try(close(cli))
```

## Blocking

winpipe connections can be set up to wait for requests or responses.
Similar to base connections,
[`winpipe()`](https://jslth.github.io/winpipe/reference/winpipe.md)
supports a `blocking` argument. If set to `TRUE`, the connection blocks
the R session until the other side of the pipe responds. To exemplify, I
am going to set up a background R session using `callr`.

``` r

start_server <- function() {
  callr::r_bg(function() {
    message("Waiting for client...")
    srv <- winpipe::winpipe(
      "winpipe-block",
      open = "w",
      server = TRUE,
      blocking = TRUE
    )
    message("A client connected!")
    Sys.sleep(3)
    writeLines("hello", srv)
    close(srv)
  })
}
```

Until a client connects, the server will keep waiting and blocking.

``` r

srv <- start_server()
while (!np_exists("winpipe-block")) Sys.sleep(0.1)
cat(srv$read_error())
#> Waiting for client...
```

When a non-blocking client connects, it will return immediately and
return nothing because the server did not have the time to respond.

``` r

cli <- winpipe(
  "winpipe-block",
  open = "r",
  server = FALSE,
  blocking = FALSE
)

system.time(x <- readLines(cli))
#>    user  system elapsed 
#>       0       0       0

x
#> character(0)

close(cli)
srv$kill()
#> [1] TRUE
```

When a blocking client connects, it will wait until the server has
responded and thus return the server’s greeting.

``` r

srv <- start_server()
while (!np_exists("winpipe-block")) Sys.sleep(0.1)

cli <- winpipe(
  "winpipe-block",
  open = "r",
  server = FALSE,
  blocking = TRUE
)

system.time(x <- readLines(cli, n = 1))
#>    user  system elapsed 
#>    0.00    0.00    2.97

x
#> [1] "hello"

close(cli)
srv$kill()
#> [1] FALSE
```

### Controlling the blocking status

By default, the session is blocked for 60 seconds
(`getOption("timeout")`), but you can control the timeout using the
`timeout` argument.

``` r

srv <- winpipe("winpipe-block", server = TRUE, blocking = TRUE, timeout = 1)
#> Error in `open.connection()`:
#> ! Timed out after 1.0 s waiting for a client
```

The timeout can be controlled after pipe creation.

``` r

srv <- winpipe("winpipe-block", server = TRUE, timeout = 1)
np_set_timeout(srv, 3)
np_get_timeout(srv)
#> [1] 3

close(srv)
```

Another way to stop blocking, of course, is to interrupt the execution.

``` r

srv <- start_server()
while (!np_exists("winpipe-block")) Sys.sleep(0.1)
srv$interrupt()
#> [1] TRUE
Sys.sleep(0.5)
cat(srv$read_error())
#> Waiting for client...
#> 
#> Error in open.connection(con, open = open, blocking = blocking, ...) : 
#>   Interrupted while waiting for a client
```

A non-blocking winpipe can be made blocking by using
[`np_listen()`](https://jslth.github.io/winpipe/reference/winpipe.md):

``` r

srv <- winpipe("winpipe-noblock", server = TRUE)
np_listen(srv, timeout = 1)
#> Error in `cpp_np_conn_accept()`:
#> ! Timed out after 1.0 s waiting for a client

close(srv)
```

### Peeking

Even when non-blocking the request/response behavior can be controlled
using peeking. Peeking allows us to retrieve the size of a payload
before reading it and to check *if* a message was delivered and *how
big* it is. After reading it, the payload is consumed.

``` r

srv <- winpipe("example-peek", server = TRUE)
cli <- winpipe("example-peek", server = FALSE)

writeLines("here is a payload", cli)
np_peek(srv)
#> [1] 18

readLines(srv)
#> [1] "here is a payload"
np_peek(srv)
#> [1] 0
```

This opens two mechanisms. First, this lets you implement custom
blocking reads with callbacks. In this example, the server waits until a
minimum payload size of 50 bytes was sent. This allows the client to
stagger the request.

``` r

while (np_peek(srv) < 50) {
  writeLines("and another one", cli)
  message("payload not big enough")
  Sys.sleep(0.5)
}
#> payload not big enough
#> payload not big enough
#> payload not big enough
#> payload not big enough
readLines(srv)
#> [1] "and another one" "and another one" "and another one" "and another one"
```

Second, it opens possibilities to handle payloads based on their size.
In this example, the server accepts only payloads with less than 20
bytes. If the client sends a larger one, it declines and closes the pipe
instance.

``` r

writeLines("here is a really really really big payload")
#> here is a really really really big payload
if (np_peek(srv) > 20) {
  writeLines("payload is too big", srv)
  close(srv)
}

readLines(cli)
#> character(0)

close(cli)
```

## Security descriptors

Who may connect to a pipe, and what they may do once connected, is
controlled by a security descriptor (SD) that the server sets when it
creates the pipe. By default,
[`winpipe()`](https://jslth.github.io/winpipe/reference/winpipe.md) uses
[`sd_default()`](https://jslth.github.io/winpipe/reference/security_descriptor.md),
the default DACL of the current token. You can inspect the SD of any
pipe with
[`np_sd()`](https://jslth.github.io/winpipe/reference/info.md).

``` r

srv <- winpipe("example-sd", server = TRUE)
np_sd(srv)
#> <winpipe_sd>
#> O:BAG:S-1-5-21-3289802278-1561746829-1498425070-513D:(A;;FA;;;BA)(A;;FA;;;SY)(A;;0x1200a9;;;S-1-5-5-0-771692)
```

Each entry in parentheses is an access control entry (ACE) that allows
or denies a set of rights to an account. To build your own, create ACEs
with [`ace()`](https://jslth.github.io/winpipe/reference/ace.md) and
collect them with
[`sd_create()`](https://jslth.github.io/winpipe/reference/security_descriptor.md).
Accounts can be well-known names such as `"everyone"` or
`"local system"`, or a SID. To refer to ourselves, we can read our own
SID from the token information, which is available once a client has
sent data.

``` r

cli <- winpipe("example-sd", server = FALSE)
writeLines("hello", cli)
readLines(srv)
#> [1] "hello"
me <- np_token_info(srv)$sid
close(cli)
close(srv)
```

### Limiting what a client may do

A client opens a pipe with the rights it needs: reading needs read
access and writing needs write access. If the SD only grants read
access, a client can read but not write.

``` r

read_only <- sd_create(ace(rights = "generic read", account = me))
read_only
#> <winpipe_sd>
#> D:(A;;GR;;;S-1-5-21-3289802278-1561746829-1498425070-500)

srv <- winpipe("example-sd", sddl = read_only)

# Reading is allowed
cli <- winpipe("example-sd", open = "r", server = FALSE)
close(cli)

# Writing is not
cli <- winpipe("example-sd", open = "w", server = FALSE)
#> Error in `open.connection()`:
#> ! Access is denied. (error 5)
close(srv)
```

### Locking clients out

ACEs are evaluated in order, and a matching *deny* ACE overrides a later
allow. Here, everyone is allowed access, but we deny ourselves first. As
a result, even the user who created the pipe cannot connect to it.

``` r

deny_me <- sd_create(
  ace("deny", rights = "generic all", account = me),
  ace("allow", rights = "generic all", account = "everyone")
)
deny_me
#> <winpipe_sd>
#> D:(D;;GA;;;S-1-5-21-3289802278-1561746829-1498425070-500)(A;;GA;;;WD)

srv <- winpipe("example-sd", sddl = deny_me)
cli <- winpipe("example-sd", server = FALSE)
#> Error in `open.connection()`:
#> ! Access is denied. (error 5)
close(srv)
```

The same mechanism lets you restrict a pipe to a specific user or group
on a shared machine. For instance, to grant access only to members of
the local Administrators group, you would use
`ace(rights = "generic all", account = "admins")`.
