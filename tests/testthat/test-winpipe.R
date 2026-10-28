if (np_exists("test")) {
  stop("Named pipe 'test' exists on the system. Make sure to close it before testing.")
}


test_that("winpipes are properly asserted first", {
  expect_error(winpipe(c("a", "b")), "string")
  expect_error(winpipe(1), "string")
  expect_error(winpipe("test", max_instances = -5), "max_instances")
  expect_error(winpipe("test", max_instances = "a"), "max_instances")
  expect_error(winpipe("test", max_instances = 1000), "max_instances")
  expect_error(winpipe("test", timeout = "a"), "timeout")
  expect_error(winpipe("test", timeout = -1), "timeout")
  expect_error(winpipe("test", sddl = 1), "sddl")
  expect_error(check_winpipe("test"), "winpipe")
})


test_that("can open server", {
  expect_false(np_exists("test"))
  srv <- winpipe("test")
  on.exit(close(srv), add = TRUE)
  expect_true(np_exists("test"))
  expect_true(np_exists("\\\\.\\pipe\\test"))
})


test_that("sd is passed correctly", {
  sd <- sd_create(ace(rights = "FA", account = "admins"))
  pipe <- winpipe("test", sddl = sd)
  on.exit(close(pipe), add = TRUE)
  sd_parsed <- np_sd(pipe)
  expect_equal(sd$dacl, sd_parsed$dacl)
})


test_that("max instances are passed correctly", {
  pipe <- winpipe("test", max_instances = 2)
  on.exit(close(pipe), add = TRUE)
  config <- np_config(pipe)
  expect_equal(config$max_instances, 2)
})


test_that("pipe can transfer", {
  srv <- winpipe("test")
  cli <- winpipe("test")
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)

  expect_length(readLines(srv), 0)
  writeLines("hello world", cli)
  expect_equal(readLines(srv), "hello world")
  expect_length(readLines(srv), 0)
})


test_that("server can peek", {
  srv <- winpipe("test")
  cli <- winpipe("test")
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)

  expect_equal(np_peek(srv), 0)
  expect_equal(np_peek(cli), 0)

  writeLines("hello\nworld", cli)
  expect_equal(np_peek(srv), 12)

  readLines(srv, n = 1)
  expect_equal(np_peek(srv), 6)

  writeLines("hello\nback", srv)
  expect_equal(np_peek(cli), 11)
})


test_that("multiple instances work", {
  srv1 <- winpipe("test")
  srv2 <- winpipe("test", server = TRUE)
  cli1 <- winpipe("test", server = FALSE)
  cli2 <- winpipe("test", server = FALSE)
  on.exit(close(cli1), add = TRUE)
  on.exit(close(cli2), add = TRUE)
  on.exit(close(srv1), add = TRUE)
  on.exit(close(srv2), add = TRUE)
  
  expect_equal(np_state(srv1)$current_instances, 2)

  # fifo works: srv1 is assigned cli1
  writeLines("hello world", cli1)
  expect_equal(np_peek(srv1), 12)
  expect_equal(np_peek(srv2), 0)
})


test_that("server stops blocking after client closes", {
  srv <- callr::r_bg(function() {
    srv <- winpipe::winpipe("test", server = TRUE, blocking = TRUE)
    on.exit(close(srv))
    readLines(srv, n = -1)
  }, package = "winpipe")
  on.exit(srv$kill(), add = TRUE)
  srv$wait(2000)

  expect_true(np_exists("test"))
  expect_true(srv$is_alive()) # server is blocking
  cli <- winpipe("test", server = FALSE) # server accepts clients
  on.exit(try(close(cli), silent = TRUE), add = TRUE)
  writeLines("hello world", cli)
  close(cli)
  srv$wait(2000)
  expect_equal(srv$get_result(), "hello world")
})


test_that("blocking can be interrupted", {
  srv <- callr::r_bg(function() {
    srv <- winpipe::winpipe("test", server = TRUE, blocking = TRUE)
    on.exit(close(srv))
    readLines(srv, n = -1)
  }, package = "winpipe")
  on.exit(srv$kill())
  expect_equal(srv$read_error(), "")

  srv$wait(2000)
  srv$interrupt()
  Sys.sleep(3)
  srv$read_error() # clean error connection
  expect_match(srv$read_error(), "Interrupted")
})


test_that("client stops blocking when a server is found", {
  # create and serve the pipe
  srv1 <- winpipe("test", server = TRUE)
  cli1 <- winpipe("test", server = FALSE)
  on.exit(close(cli1), add = TRUE)
  on.exit(close(srv1), add = TRUE)

  # create a new unserved pipe
  cli2 <- callr::r_bg(function(pkg_path) {
    is_source <- file.exists(file.path(pkg_path, "DESCRIPTION")) &&
      !dir.exists(file.path(pkg_path, "Meta"))

    if (is_source) {
      pkgload::load_all(pkg_path, quiet = TRUE)
    } else {
      library(winpipe)
    }
    cli <- winpipe("test", server = FALSE, blocking = TRUE)
    on.exit(close(cli))
    writeLines("hello world", cli)
  }, args = list(pkg_path = testthat::test_path("../..")))
  on.exit(cli2$kill(), add = TRUE)
  cli2$wait(2000)

  expect_true(cli2$is_alive()) # still searching?
  srv2 <- winpipe("test", server = TRUE) # serve it
  on.exit(close(srv2), add = TRUE)
  cli2$wait(4000)
  expect_false(cli2$is_alive()) # client happy
})


test_that("clients can be disconnected", {
  srv <- winpipe("test", server = TRUE)
  cli <- winpipe("test", server = FALSE)
  on.exit(close(srv), add = TRUE)
  on.exit(close(cli), add = TRUE)
  expect_false(is.na(np_state(srv)$username))
  expect_true(np_connected(cli))
  expect_true(np_connected(srv))
  np_disconnect(srv)
  expect_true(is.na(np_state(srv)$username))
  expect_false(np_connected(cli))
})


test_that("timeouts can be set post-hoc", {
  pipe <- winpipe("test")
  on.exit(close(pipe), add = TRUE)
  old <- np_get_timeout(pipe)
  expect_equal(np_set_timeout(pipe, 200), old)
  expect_equal(np_get_timeout(pipe), 200)
})


test_that("peeking is liberal", {
  srv <- winpipe("test")
  on.exit(close(srv), add = TRUE)
  expect_warning(np_peek(srv), "error 230[)]")
  expect_equal(suppressWarnings(np_peek(srv)), 0)
})


test_that("named pipes can be listed", {
  expect_vector(np_list(), character())
})