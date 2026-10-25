# Named pipe timeouts

Get or set the I/O timeout of a pipe connection

## Usage

``` r
np_set_timeout(con, timeout)

np_get_timeout(con)
```

## Arguments

- con:

  `[winpipe]`.

  An open `winpipe` as created by
  [`winpipe`](https://jslth.github.io/winpipe/reference/winpipe.md).

- timeout:

  `[numeric]`

  New timeout in seconds. Can be `Inf` to wait forever.

## Value

`np_get_timeout` returns the current timeout of a `winpipe`.
`np_set_timeout` returns the previous timeout before setting.

## Examples

``` r
np <- winpipe("test")
on.exit(close(np))

np_get_timeout(np)
#> Error in cpp_np_conn_timeout(con, 0, FALSE): invalid connection
np_set_timeout(np, Inf)
#> Error in cpp_np_conn_timeout(con, as.double(timeout), TRUE): invalid connection
np_get_timeout(np)
#> Error in cpp_np_conn_timeout(con, 0, FALSE): invalid connection
```
