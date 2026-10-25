# Security token information

Query the Windows access token associated with a named pipe client or
with the calling R process.

`np_whoami()` returns information about a token's user.
`np_token_info()` returns the full token details.

## Usage

``` r
np_whoami(con = NULL)

np_token_info(con = NULL)
```

## Arguments

- con:

  `[winpipe]` or `NULL`.

  The server end of a connected pipe, to query the connected client's
  token, or `NULL` (default) to query the token of the R process itself.

## Value

`np_whoami()` returns a string of the form `"DOMAIN\user"`.

`np_token_info()` returns a list with:

- `user`: user name as `"DOMAIN\user"`.

- `sid`: user SID string.

- `groups`: a data frame of group names, SIDs, and whether each group is
  enabled.

- `elevated`: whether the token is elevated (UAC).

- `integrity`: integrity level (`"low"`, `"medium"`, `"high"`, or
  `"system"`).

- `token_type`: `"primary"` (own process) or `"impersonation"` (pipe
  client).

- `impersonation_level`: for impersonation tokens, one of `"anonymous"`,
  `"identification"`, `"impersonation"`, or `"delegation"`; `NA` for
  primary tokens.

## Examples

``` r
# If no argument is provided, returns the SID
# of the R session
np_whoami()
#> [1] "runnervmdaln5\\runneradmin"

# If a server-client structure is provided
# returns the SID of the client
server <- winpipe("test")
client <- winpipe("test")
np_whoami(server)
#> [1] "S-1-5-21-3776380004-1005456608-3524014338-500"

close(client)
close(server)
```
