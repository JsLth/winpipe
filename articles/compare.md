# fifo() vs. processx vs. winpipe

R can talk to Windows named pipes in three ways: base R’s
[`fifo()`](https://rdrr.io/r/base/connections.html),
[`processx::conn_create_fifo()`](http://processx.r-lib.org/reference/processx_fifos.md)
and
[`processx::conn_connect_fifo()`](http://processx.r-lib.org/reference/processx_fifos.md),
and winpipe. They behave quite differently on Windows. This vignette
shows what each can and cannot do, using a small external server written
in PowerShell as the peer.

``` r

library(winpipe)
library(processx)
```

## A test peer

Named pipes live in the `\\.\pipe\` namespace. Every pipe on the machine
is listed by `list.files("//./pipe/")`, but the ones that ship with
Windows are access controlled, so they make poor examples. Instead, I
create a helper function `ps_server()` that starts a tiny server using
the PowerShell. Open the details below to see how it works.

Code for the named pipe helper

``` r

ps_script <- tempfile(fileext = ".ps1")
writeLines('
param($name, $mode, $msg, $log)
$dir = if ($mode -eq "out8" -or $mode -eq "out16") { "Out" }
       elseif ($mode -eq "in") { "In" } else { "InOut" }
$s = New-Object System.IO.Pipes.NamedPipeServerStream($name, [System.IO.Pipes.PipeDirection]::$dir)
$s.WaitForConnection()
if ($mode -eq "out8") {
  $w = New-Object System.IO.StreamWriter($s)
  $w.WriteLine($msg); $w.Flush()
} elseif ($mode -eq "out16") {
  $enc = New-Object System.Text.UnicodeEncoding($false, $false)
  $w = New-Object System.IO.StreamWriter($s, $enc)
  $w.WriteLine($msg); $w.Flush()
} elseif ($mode -eq "echo") {
  $r = New-Object System.IO.StreamReader($s)
  $w = New-Object System.IO.StreamWriter($s)
  $line = $r.ReadLine()
  # The client may already be gone, e.g., if it failed to write
  try { $w.WriteLine("echo: $line"); $w.Flush() } catch {}
} else {
  $r = New-Object System.IO.StreamReader($s)
  $r.ReadLine() | Out-File -Encoding ascii $log
}
Start-Sleep -Milliseconds 1000
$s.Dispose()
', ps_script)

ps_server <- function(name, mode, msg = "", log = "") {
  system2(
    "powershell",
    c("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", shQuote(ps_script),
      name, mode, shQuote(msg), shQuote(log)),
    wait = FALSE
  )

  for (i in 1:100) {
    if (name %in% list.files("//./pipe/")) return(invisible())
    Sys.sleep(0.1)
  }
  stop("Pipe '", name, "' was not created")
}
```

`ps_server()` starts a server in the background. Its `mode` decides what
it does once a client connects: send a line as UTF-8 (`"out8"`) or
UTF-16 (`"out16"`), read a line (`"in"`), or echo a line back
(`"echo"`).

## `fifo()`

On Unix, [`fifo()`](https://rdrr.io/r/base/connections.html) opens a
FIFO that you create with `mkfifo`. On Windows, R implements it with
Win32 named pipes, but with different semantics:

- Opening for reading (`"r"`) connects to an existing pipe as a client.
- Opening for writing (`"w"`) *creates* the pipe, i.e., R becomes the
  server. It cannot connect to a pipe that already exists.
- Data is read and written as UTF-16, not as bytes.

The last point is easy to miss. If the peer sends ordinary UTF-8 or
ASCII text, [`readLines()`](https://rdrr.io/r/base/readLines.html)
returns nothing:

``` r

ps_server("demo-fifo-utf8", "out8", "hello from powershell")

con <- fifo("\\\\.\\pipe\\demo-fifo-utf8", "r", blocking = FALSE)
for (i in 1:10) {
  res <- readLines(con)
  if (length(res)) break
  Sys.sleep(0.2)
}
res
#> character(0)
close(con)
```

The connection opened without error, the server saw the client, but the
bytes were decoded as wide characters and discarded. If the peer happens
to send UTF-16, the text arrives:

``` r

ps_server("demo-fifo-utf16", "out16", "hello from powershell")

con <- fifo("\\\\.\\pipe\\demo-fifo-utf16", "r", blocking = FALSE)
for (i in 1:10) {
  res <- readLines(con)
  if (length(res)) break
  Sys.sleep(0.2)
}
res
#> [1] "hello from powershell"
close(con)
```

Because `"w"` creates the pipe,
[`fifo()`](https://rdrr.io/r/base/connections.html) also cannot write to
an existing server. Opening in `"r+"` mode connects, but writing fails:

``` r

ps_server("demo-fifo-echo", "echo")

con <- fifo("\\\\.\\pipe\\demo-fifo-echo", "r+", blocking = FALSE)
try(writeLines("hello", con))
#> Error in writeLines("hello", con) : cannot write to this connection
close(con)
```

So [`fifo()`](https://rdrr.io/r/base/connections.html) can be used
between two R processes that both expect UTF-16, but not to talk to an
arbitrary program. A request/response protocol such as HTTP is not
possible.

## processx

processx provides its own connection type that works on both Unix and
Windows. The reading end creates a pipe with
[`conn_create_fifo()`](http://processx.r-lib.org/reference/processx_fifos.md),
and a writer attaches to it with
[`conn_connect_fifo()`](http://processx.r-lib.org/reference/processx_fifos.md):

``` r

reader <- conn_create_fifo()
writer <- conn_connect_fifo(conn_file_name(reader), write = TRUE)

conn_write(writer, "hello\nthere\n")
poll(list(reader), 1000)
#> [[1]]
#> [1] "ready"
conn_read_lines(reader, 1)
#> [1] "hello"

close(writer)
#> NULL
close(reader)
#> NULL
```

It also connects to pipes created by other programs. Unlike
[`fifo()`](https://rdrr.io/r/base/connections.html), it reads bytes, so
UTF-8 text from our PowerShell server arrives intact:

``` r

ps_server("demo-px", "out8", "hello from powershell")

con <- conn_connect_fifo("\\\\?\\pipe\\demo-px", read = TRUE)
poll(list(con), 2000)
#> [[1]]
#> [1] "ready"
conn_read_lines(con, 1)
#> [1] "hello from powershell"
close(con)
#> NULL
```

The limits are in the design:

- A connection is one-directional. A pipe created by
  [`conn_create_fifo()`](http://processx.r-lib.org/reference/processx_fifos.md)
  can only be read from, and a connection made with `write = TRUE` can
  only write. A request/response exchange over a single pipe does not
  fit.
- The connections are `processx_connection` objects, not R connections.
  [`readLines()`](https://rdrr.io/r/base/readLines.html),
  [`read.csv()`](https://rdrr.io/r/utils/read.table.html),
  [`writeBin()`](https://rdrr.io/r/base/readBin.html) etc. do not work
  on them.
- There is no way to set a security descriptor.

## winpipe

winpipe exposes a Win32 named pipe as a native R connection. A client
connects with `server = FALSE`, can read and write on the same pipe, and
every R function that accepts a connection works. The echo server
demonstrates the request/response exchange:

``` r

ps_server("demo-wp-echo", "echo")

con <- winpipe("demo-wp-echo", open = "r+", server = FALSE)
writeLines("hello", con)
Sys.sleep(0.5)
readLines(con)
#> [1] "echo: hello"
close(con)
```

winpipe also reads UTF-8 from external servers, like processx:

``` r

ps_server("demo-wp-out8", "out8", "hello from powershell")

con <- winpipe("demo-wp-out8", open = "r", server = FALSE)
Sys.sleep(0.5)
readLines(con)
#> [1] "hello from powershell"
close(con)
```

Opening the client with `"r"` or `"w"` requests only that access, so it
can also connect to one-way pipes such as the processx reader:

``` r

reader <- conn_create_fifo()
name <- sub("^\\\\\\\\[.?]\\\\pipe\\\\", "", conn_file_name(reader))

client <- winpipe(name, open = "w", server = FALSE)
writeLines("hello from winpipe", client)

poll(list(reader), 2000)
#> [[1]]
#> [1] "ready"
conn_read_lines(reader, 1)
#> [1] "hello from winpipe"

close(client)
close(reader)
#> NULL
```

winpipe can also be the server, accept clients without blocking the R
session, and take a security descriptor. See
[`vignette("basics")`](https://jslth.github.io/winpipe/articles/basics.md).

## Summary

|  | [`fifo()`](https://rdrr.io/r/base/connections.html) | processx | winpipe |
|:---|:---|:---|:---|
| Connection type | R connection | `processx_connection` | R connection |
| Platforms | Unix and Windows | Unix and Windows | Windows only |
| Connect to existing pipe | read only | yes (one direction) | yes |
| Create a pipe (server) | write mode only | reading end | yes |
| Bidirectional | no | no | yes |
| Text encoding on Windows | UTF-16 | bytes | bytes |
| Talk to non-R programs | not reliably | one direction | yes |
| Non-blocking | yes | yes, via [`poll()`](http://processx.r-lib.org/reference/poll.md) | yes |
| Access control (SDDL) | no | no | yes |

The behaviour of [`fifo()`](https://rdrr.io/r/base/connections.html) and
processx described above was observed on Windows with R 4.6 and may
differ on other versions.
