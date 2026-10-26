# Proxies

Starts a local relay proxy for a named pipe. The relay proxy lives in a
background process through
[`r_bg`](https://callr.r-lib.org/reference/r_bg.html).

Essentially, this is a way to communicate with named pipes through HTTP
requests. The relay server takes HTTP requests from a client (e.g. with
`curl` or `httr2`), sends them to the named pipe using a
[`winpipe`](https://jslth.github.io/winpipe/reference/winpipe.md) and
then sends the response back to the HTTP client.

`np_relay()` is the workhorse function, which contains the server socket
logic. `np_proxy()` is a simple wrapper that starts the relay server in
a background process in order to not block the main session.

## Usage

``` r
np_proxy(name, port = httpuv::randomPort(), relay = np_relay)

np_relay(name, port)
```

## Arguments

- name:

  `[character(1)]`

  Pipe name, with or without the `\\.\pipe\` prefix.

- port:

  `[numeric(1)]`

  TCP port that the relay server should listen on.

- relay:

  `[function]`

  A relay function that takes a named pipe name and a port and forwards
  requests and responses between a server and a client. Defaults to
  `np_relay`.

## Value

`np_proxy()` returns an object of class `winpipe_proxy`. This object
contains the base URL that accepts requests and a
[`process`](http://processx.r-lib.org/reference/process.md) object that
manages the server child process. `np_relay()` returns nothing but runs
a server that accepts requests as long as the function is running.

## Examples

``` r
# np_proxy() is a good way to communicate with named pipes
# that communicate over HTTP, e.g., docker
if (np_exists("docker_engine") && requireNamespace("httr2")) {
library(httr2)

proxy <- np_proxy("docker_engine")

# GET requests, e.g., to query the docker version
resp <- request(proxy$base_url) %>%
  req_url_path("/version") %>%
  req_perform() %>%
  resp_body_json()
resp[c("Version", "ApiVersion", "Os")]

# POST requests, e.g., to create a container
# do not run this if you don't wish to modify your docker state
if (FALSE) { # \dontrun{
# pull image
pull <- request(proxy$base_url) %>%
  req_url_path("/images/create") %>%
  req_url_query(fromImage = "hello-world", tag = "latest") %>%
  req_method("POST") %>%
  req_perform()
pull$status_code

# create container
created <- request(proxy$base_url) %>%
  req_url_path("/containers/create") %>%
  req_url_query(name = "winpipe-test") %>%
  req_body_json(list(Image = "hello-world:latest")) %>%
  req_perform()
created$status_code
} # }
}
```
