# HTTP over named pipes

``` r

library(winpipe)
```

Sometimes, named pipes communicate over HTTP requests. One example for
this is docker, which exposes paths like `/version` over named pipes on
Windows. These requests work like any other pipe and, technically, can
be communicated with like so:

``` r

# check if docker is running
# start docker desktop if not
np_exists("docker_engine")
#> [1] FALSE

# Connect to docker
pipe <- winpipe("docker_engine", open = "r+b", server = FALSE)
#> Error in `open.connection()`:
#> ! Das System kann die angegebene Datei nicht finden.

# Manually craft a request
req <- paste(
  "GET /version HTTP/1.1",
  "Host: localhost",
  "Connection: close",
  "\r\n",
  sep = "\r\n"
)

# Send the request
writeBin(charToRaw(req), pipe)
#> Error in `writeBin()`:
#> ! invalid connection

# Read the response
res <- tryCatch(readBin(pipe, "raw", 65536))
#> Error in `readBin()`:
#> ! invalid connection

close(pipe)
#> Error in `UseMethod()`:
#> ! no applicable method for 'close' applied to an object of class "function"
cat(rawToChar(res))
#> Error:
#> ! object 'res' not found
```

And while this is technically a solution, you have to take care of
proper HTTP handling yourself, that is, making requests, parsing
responses and all the nitty gritty in between. R already has ways to
handle HTTP with packages such as
[curl](https://jeroen.r-universe.dev/curl),
[crul](https://docs.ropensci.org/crul/) or
[httr2](https://httr2.r-lib.org).

[`np_proxy()`](https://jslth.github.io/winpipe/reference/proxy.md) is a
little helper than creates a relay socket server between server and
client. It can thus communicate with a named pipe but can take HTTP
requests like a normal socket server. There are two downsides:

- Socket servers are not protected by Windows security
- Proxies block the session and have to be run in a background process

To start a proxy, simply provide the name of a named pipe:

``` r

proxy <- np_proxy("docker_engine")
proxy
#> <winpipe_proxy>
#>   winpipe:   \\.\pipe\docker_engine 
#>   base url:  http://127.0.0.1:9863/ 
#>   listening: yes
```

The base URL shown in the console is the server you can connect to. The
“listening” simply means that the background server hasn’t died yet. You
can now send requests through curl, like so:

``` r

library(httr2)

resp <- request(proxy$base_url) %>%
  req_url_path("/version") %>%
  req_perform() %>%
  resp_body_json()
#> Error in `req_perform()`:
#> ! Failed to perform HTTP request.
#> Caused by error in `curl::curl_fetch_memory()`:
#> ! Failure when receiving data from the peer [127.0.0.1]:
#> Recv failure: Connection was reset
resp$Platform
#> Error:
#> ! object 'resp' not found
```

POST and DELETE requests work, too. For example, to download or delete
an image:

``` r

pull <- request(proxy$base_url) %>%
  req_url_path("/images/create") %>%
  req_url_query(fromImage = "hello-world", tag = "latest") %>%
  req_method("POST") %>%
  req_perform() %>%
  resp_body_string()
#> Error in `req_perform()`:
#> ! Failed to perform HTTP request.
#> Caused by error in `curl::curl_fetch_memory()`:
#> ! Could not connect to server [127.0.0.1]:
#> Failed to connect to 127.0.0.1 port 9863 after 2032 ms: Could not connect to server
cat(pull)
#> Error:
#> ! object 'pull' not found
```

``` r

img <- request(proxy$base_url) %>%
  req_url_path("/images/json") %>%
  req_perform() %>%
  resp_body_json(simplifyVector = TRUE)
#> Error in `req_perform()`:
#> ! Failed to perform HTTP request.
#> Caused by error in `curl::curl_fetch_memory()`:
#> ! Could not connect to server [127.0.0.1]:
#> Failed to connect to 127.0.0.1 port 9863 after 2055 ms: Could not connect to server
id <- img$Id
#> Error:
#> ! object 'img' not found

del <- request(proxy$base_url) %>%
  req_url_path("/images", id) %>%
  req_method("DELETE") %>%
  req_perform()
#> Error:
#> ! object 'id' not found
del$status_code
#> Error:
#> ! object 'del' not found
```

Since proxies are background R processes, you have to handle them like
one. To close a named pipe, kill the process.

``` r

proxy$proc
#> PROCESS 'Rterm', finished.
```

``` r

proxy$proc$kill()
#> [1] FALSE
```
