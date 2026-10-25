test_that("np_proxy validates its input", {
  skip_if_not_installed("callr")
  expect_error(np_proxy(1), "`name`")
  expect_error(np_proxy("x", port = -1), "`port`")
  expect_error(np_proxy("x", port = "a"), "`port`")
})


test_that("np_proxy requires callr", {
  local_mocked_bindings(is_installed = function(x) FALSE)
  expect_error(np_proxy("x"), "callr")
  expect_error(random_port(), "httpuv")
})


test_that("random_port returns a port", {
  skip_if_not_installed("httpuv")
  expect_true(is_number(random_port()))
})


test_that("has_end finds header terminators", {
  expect_false(has_end(charToRaw("GET / HTTP/1.1")))
  expect_false(has_end(raw(0)))
  expect_true(has_end(charToRaw("GET / HTTP/1.1\r\nHost: a\r\n\r\n")))
})


test_that("proxies print their state", {
  skip_if_not_installed("callr")
  proxy <- np_proxy("x", port = 54321, relay = function(name, port) Sys.sleep(60))
  on.exit(proxy$proc$kill(), add = TRUE)

  expect_output(res <- print(proxy), "<winpipe_proxy>")
  expect_identical(res, proxy)
  expect_output(print(proxy), "yes")

  proxy$proc$kill()
  expect_output(print(proxy), "no")
})


# np_relay() runs in a loop; stop it after `n` requests by erroring out of
# socketAccept().
limited_relay <- function(n) {
  relay <- np_relay
  count <- 0
  env <- new.env(parent = asNamespace("winpipe"))
  env$socketAccept <- function(...) {
    count <<- count + 1
    if (count > n) stop("relay done")
    base::socketAccept(...)
  }
  environment(relay) <- env
  relay
}


send_requests <- function(port, requests) {
  callr::r_bg(
    function(port, requests) {
      lapply(requests, function(req) {
        con <- NULL
        for (i in 1:100) {
          con <- tryCatch(
            socketConnection("127.0.0.1", port, open = "r+b", blocking = TRUE),
            error = function(e) NULL,
            warning = function(w) NULL
          )
          if (!is.null(con)) break
          Sys.sleep(0.2)
        }
        writeBin(charToRaw(req), con)
        out <- raw(0)
        repeat {
          chunk <- readBin(con, "raw", 65536)
          if (!length(chunk)) break
          out <- c(out, chunk)
        }
        close(con)
        rawToChar(out)
      })
    },
    args = list(port = port, requests = requests),
    supervise = TRUE
  )
}


test_that("np_relay forwards requests to a pipe", {
  skip_if_not_installed("callr")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")

  handler <- function(req) {
    if (req$method == "POST") {
      list(status = 201L, body = rawToChar(req$body))
    } else {
      list(status = 200L, body = "hello")
    }
  }
  mock <- start_mock("relay-test", handler, n = 2)
  on.exit(mock$kill(), add = TRUE)

  port <- httpuv::randomPort()
  client <- send_requests(port, list(
    "GET /a HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n",
    "POST /b HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nabcde"
  ))
  on.exit(client$kill(), add = TRUE)

  expect_error(limited_relay(2)("relay-test", port), "relay done")

  client$wait(10000)
  res <- client$get_result()
  expect_match(res[[1]], "^HTTP/1.1 200")
  expect_match(res[[1]], "hello$")
  expect_match(res[[2]], "^HTTP/1.1 201")
  expect_match(res[[2]], "abcde$")
})


test_that("np_relay reports pipe errors and keeps going", {
  skip_if_not_installed("callr")
  skip_if_not_installed("httpuv")

  port <- httpuv::randomPort()
  client <- send_requests(port, list("GET / HTTP/1.1\r\nHost: x\r\n\r\n"))
  on.exit(client$kill(), add = TRUE)

  # The relay reports the error through message(), which signals it as a
  # condition; catching it here ends the relay.
  err <- tryCatch(limited_relay(1)("relay-missing", port), error = identity)
  expect_match(conditionMessage(err), "cannot find")
})
