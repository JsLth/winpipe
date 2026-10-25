# Reads a line of a connection and splits spaces
read_line <- function(con) {
  buf <- raw(0)
  repeat {
    b <- readBin(con, "raw", 1L)
    if (!length(b)) stop("Connection closed while reading a line.")
    if (b == as.raw(10L)) break
    buf <- c(buf, b)
  }
  n <- length(buf)
  if (n && buf[n] == as.raw(13L)) buf <- buf[-n]
  rawToChar(buf)
}

read_chunked <- function(con) {
  body <- raw(0)
  repeat {
    size_line <- read_line(con)
    size <- strtoi(strsplit(size_line, ";", fixed = TRUE)[[1]][1], base = 16L)
    if (is.na(size)) stop("Invalid chunk size: ", size_line)
    if (size == 0L) break
    body <- c(body, readBin(con, "raw", size))
    read_line(con)
  }
  # Skip trailers
  while (nzchar(read_line(con))) NULL
  body
}

read_http_request <- function(con) {
  start <- strsplit(read_line(con), " ", fixed = TRUE)[[1]]
  if (length(start) != 3L) stop("Malformed request line.")

  headers <- list()
  repeat {
    line <- read_line(con)
    if (!nzchar(line)) break
    pos <- regexpr(":", line, fixed = TRUE)
    name <- tolower(substr(line, 1L, pos - 1L))
    headers[[name]] <- trimws(substr(line, pos + 1L, nchar(line)))
  }

  body <- if (identical(tolower(headers[["transfer-encoding"]]), "chunked")) {
    read_chunked(con)
  } else if (!is.null(headers[["content-length"]])) {
    readBin(con, "raw", as.integer(headers[["content-length"]]))
  } else {
    raw(0)
  }

  url <- httr2::url_parse(paste0("http://localhost", start[2]))
  list(
    method = start[1],
    target = start[2],
    path = url$path,
    query = url$query,
    version = start[3],
    headers = headers,
    body = body
  )
}

write_http_response <- function(con,
                                status = 200L,
                                body = raw(0),
                                headers = list()) {
  if (is.character(body)) {
    body <- charToRaw(body)
  }

  reasons <- c(
    `200` = "OK",
    `201` = "Created",
    `204` = "No Content",
    `400` = "Bad Request",
    `404` = "Not Found",
    `500` = "Internal Server Error"
  )

  headers[["Content-Length"]] <- length(body)
  headers[["Connection"]] <- "close"
  head <- paste0(
    "HTTP/1.1 ",
    status,
    " ",
    reasons[as.character(status)],
    "\r\n",
    paste0(
      names(headers),
      ": ",
      unlist(headers),
      "\r\n",
      collapse = ""
    ),
    "\r\n"
  )

  writeBin(c(charToRaw(head), body), con)
}

mock_server <- function(name, handler, n = 1L) {
  srv <- winpipe::winpipe(
    name,
    open = "r+b",
    server = TRUE,
    blocking = FALSE,
    timeout = 60
  )

  for (i in seq_len(n)) {
    winpipe::np_listen(srv)
    res <- tryCatch(
      handler(read_http_request(srv)),
      error = function(e) {
        list(status = 500L, body = conditionMessage(e))
      }
    )

    write_http_response(
      srv,
      res$status %||% 200L,
      res$body %||% raw(0),
      res$headers %||% list()
    )

    if (i < n) {
      nxt <- winpipe::winpipe(
        name,
        open = "r+b",
        server = TRUE,
        blocking = FALSE,
        timeout = 60
      )
    }

    close(srv)
    if (i < n) srv <- nxt
  }
}


start_mock <- function(name, handler, n = 1L, timeout = 30) {
  helper <- normalizePath(test_path("helper-http.R"), winslash = "/")
  pkg <- normalizePath(test_path("..", ".."), winslash = "/", mustWork = FALSE)

  proc <- callr::r_bg(
    function(name, handler, n, helper, pkg) {
      is_source <- file.exists(file.path(pkg, "DESCRIPTION")) &&
        !dir.exists(file.path(pkg, "Meta"))

      if (is_source) {
        pkgload::load_all(pkg, quiet = TRUE)
      } else {
        library(winpipe)
      }
      source(helper, local = TRUE)
      mock_server(name, handler, n)
    },
    args = list(name = name, handler = handler, n = n, helper = helper, pkg = pkg),
    supervise = TRUE
  )

  start <- Sys.time()
  while (!np_exists(name)) {
    if (!proc$is_alive() || difftime(Sys.time(), start, units = "secs") > timeout) {
      stop("Mock server did not start:\n", paste(proc$read_error(), collapse = "\n"))
    }
    Sys.sleep(0.1)
  }
  proc
}
