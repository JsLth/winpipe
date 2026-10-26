#' Proxies
#' 
#' @description
#' Starts a local relay proxy for a named pipe. The relay proxy
#' lives in a background process through \code{\link[callr]{r_bg}}.
#' 
#' Essentially, this is a way to communicate with named pipes
#' through HTTP requests. The relay server takes HTTP requests from
#' a client (e.g. with \code{curl} or \code{httr2}), sends them
#' to the named pipe using a \code{\link{winpipe}} and then sends
#' the response back to the HTTP client.
#' 
#' \code{np_relay()} is the workhorse function, which contains the
#' server socket logic. \code{np_proxy()} is a simple wrapper that
#' starts the relay server in a background process in order to
#' not block the main session.
#' 
#' @inheritParams winpipe
#' @param port \code{[numeric(1)]}
#' 
#' TCP port that the relay server should listen on.
#' @param relay \code{[function]}
#' 
#' A relay function that takes a named pipe name and a port and forwards
#' requests and responses between a server and a client. Defaults to
#' \code{np_relay}.
#' @returns \code{np_proxy()} returns an object of class \code{winpipe_proxy}.
#' This object contains the base URL that accepts requests and a
#' \code{\link[processx]{process}} object that manages the server child process.
#' \code{np_relay()} returns nothing but runs a server that accepts requests as
#' long as the function is running.
#' 
#' @rdname proxy
#' @export
#' 
#' @examples
#' # np_proxy() is a good way to communicate with named pipes
#' # that communicate over HTTP, e.g., docker
#' if (np_exists("docker_engine") && requireNamespace("httr2")) {
#' library(httr2)
#' 
#' proxy <- np_proxy("docker_engine")
#' 
#' # GET requests, e.g., to query the docker version
#' resp <- request(proxy$base_url) %>%
#'   req_url_path("/version") %>%
#'   req_perform() %>%
#'   resp_body_json()
#' resp[c("Version", "ApiVersion", "Os")]
#' 
#' # POST requests, e.g., to create a container
#' # do not run this if you don't wish to modify your docker state
#' \dontrun{
#' # pull image
#' pull <- request(proxy$base_url) %>%
#'   req_url_path("/images/create") %>%
#'   req_url_query(fromImage = "hello-world", tag = "latest") %>%
#'   req_method("POST") %>%
#'   req_perform()
#' pull$status_code
#' 
#' # create container
#' created <- request(proxy$base_url) %>%
#'   req_url_path("/containers/create") %>%
#'   req_url_query(name = "winpipe-test") %>%
#'   req_body_json(list(Image = "hello-world:latest")) %>%
#'   req_perform()
#' created$status_code
#' }
#' }
np_proxy <- function(name, port = httpuv::randomPort(), relay = np_relay) {
  check_installed("callr", "run a proxy in the background")

  if (!is_string(name)) {
    stop("Argument `name` must be a single string.")
  }

  if (!is_number(port) || port <= 0) {
    stop("Argument `port` must be a valid port.")
  }

  proc <- callr::r_bg(
    relay,
    args = list(
      name = name,
      port = port
    ),
    package = "winpipe",
    supervise = TRUE
  )

  url <- sprintf("http://127.0.0.1:%s/", port)
  structure(
    list(
      name = maybe_prefix(name),
      base_url = url,
      proc = proc
    ),
    class = "winpipe_proxy"
  )
}


#' @rdname proxy
#' @export
np_relay <- function(name, port) {
  srv <- serverSocket(port)
  on.exit(close(srv))
  end <- charToRaw("\r\n\r\n")

  repeat {
    cl <- socketAccept(srv, blocking = TRUE, open = "r+b", timeout = 86400)

    tryCatch(
      {
        buf <- raw(0)

        # accept user request
        repeat {
          chunk <- readBin(cl, "raw", 1L)
          if (!length(chunk)) break
          buf <- c(buf, chunk)
          if (has_end(buf)) break
        }

        # NA when the request has no Content-Length header
        len <- suppressWarnings(as.integer(sub(
          "(?is).*\r\ncontent-length:\\s*([0-9]+).*",
          "\\1",
          rawToChar(buf),
          perl = TRUE)
        ))

        body <- if (is.na(len) || len == 0L) {
          raw(0)
        } else {
          readBin(cl, "raw", len)
        }

        head <- rawToChar(buf)
        head <- sub("\r\n[Cc]onnection:[^\r]*", "", head)
        head <- sub("\r\n\r\n", "\r\nConnection: close\r\n\r\n", head, fixed = TRUE)
        
        # transfer request to named pipe
        p <- winpipe(
          name,
          open = "r+b",
          server = FALSE,
          blocking = TRUE,
          timeout = 5
        )
        writeBin(c(charToRaw(head), body), p)

        # accept response from named pipe
        repeat {
          chunk <- readBin(p, "raw", 65536)
          if (!length(chunk)) {
            break
          }

          writeBin(chunk, cl)
        }
        close(p)
      },
      error = message
    )
    close(cl)
  }
}


#' @export
print.winpipe_proxy <- function(x, ...) {
  alive <- x$proc$is_alive()

  cat(
    "<winpipe_proxy>\n",
    " winpipe:  ", x$name, "\n",
    " base url: ", x$base_url, "\n",
    " listening:", ifelse(alive, "yes", "no"), "\n"
  )
  invisible(x)
}


has_end <- function(b) {
  n <- length(b)
  n >= 4 && any(vapply(
    seq_len(n - 3),
    function(i) all(b[seq(i, i + 3)] == charToRaw("\r\n\r\n")),
    FUN.VALUE = logical(1)
  ))
}


random_port <- function() {
  check_installed("httpuv", "find a free port")
  httpuv::randomPort()
}