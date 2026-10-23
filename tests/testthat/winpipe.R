test_that("can open server", {
  expect_false(np_exists("test"))
  srv <- winpipe("test")
  on.exit(close(srv))
  expect_true(np_exists("test"))
  expect_true(np_exists("\\\\.\\pipe\\test"))
})


test_that("pipe can transfer", {
  srv <- winpipe("test")
  cli <- winpipe("test")
  on.exit(close(cli))
  on.exit(close(srv))

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
  srv <- callr::r_bg(function(pkg_path) {
    pkgload::load_all(pkg_path, quiet = TRUE)
    srv <- winpipe("test", server = TRUE, blocking = TRUE)
    on.exit(close(srv))
    readLines(srv, n = -1)
  }, args = list(pkg_path = testthat::test_path("../..")))
  srv$wait(2000)

  expect_true(np_exists("test"))
  expect_true(srv$is_alive()) # server is blocking
  cli <- winpipe("test", server = FALSE) # server accepts clients
  on.exit(close(cli))
  writeLines("hello world", cli)
  close(cli)
  expect_equal(srv$get_result(), "hello world")
})


test_that("blocking can be interrupted", {
  srv <- callr::r_bg(function(pkg_path) {
    pkgload::load_all(pkg_path, quiet = TRUE)
    srv <- winpipe("test", server = TRUE, blocking = TRUE)
    on.exit(close(srv))
    readLines(srv, n = -1)
  }, args = list(pkg_path = testthat::test_path("../..")))
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
  on.exit(close(srv1))
  on.exit(close(cli1))

  # create a new unserved pipe
  cli2 <- callr::r_bg(function(pkg_path) {
    pkgload::load_all(pkg_path, quiet = TRUE)
    cli <- winpipe("test", server = FALSE, blocking = TRUE)
    on.exit(close(cli))
    writeLines("hello world", cli)
  }, args = list(pkg_path = testthat::test_path("../..")))
  cli2$wait(2000)

  expect_true(cli2$is_alive()) # still searching?
  srv2 <- winpipe("test", server = TRUE) # serve it
  on.exit(close(srv2))
  expect_false(cli2$is_alive()) # client happy
})