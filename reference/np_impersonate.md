# Impersonation

Impersonate a client (and revert). When impersonated, pipe actions can
be executed from the client's perspective.

Currently, there's no real use for these functions. You can retrieve the
name of the client using
[`np_state`](https://jslth.github.io/winpipe/reference/info.md).

After impersonating, make sure to always revert.

## Usage

``` r
np_impersonate(con)

np_revert()
```

## Arguments

- con:

  `[winpipe]`.

  An open `winpipe` as created by
  [`winpipe`](https://jslth.github.io/winpipe/reference/winpipe.md).

## Value

Nothing.

## Examples

``` r
server <- winpipe("test")
client <- winpipe("test")
np_impersonate()
#> Error in np_impersonate(): could not find function "np_impersonate"
on.exit(np_revert())
```
