test_that("timeouts are validated and can be infinite", {
  pipe <- winpipe("test")
  on.exit(close(pipe), add = TRUE)

  expect_error(np_set_timeout(pipe, NA_real_), "non-negative")
  expect_error(np_set_timeout(pipe, -1), "non-negative")

  np_set_timeout(pipe, Inf)
  expect_equal(np_get_timeout(pipe), Inf)
  np_set_timeout(pipe, 1e10)
  expect_equal(np_get_timeout(pipe), Inf)
})


test_that("non-pipe and closed connections are rejected", {
  expect_error(winpipe:::cpp_np_conn_info(stdin()), "Not a named pipe")
  expect_error(winpipe:::cpp_np_conn_timeout(stdin(), 0, FALSE), "Not a named pipe")

  pipe <- winpipe("test", open = "")
  on.exit(close(pipe), add = TRUE)
  expect_error(np_config(pipe), "not open")
})


test_that("invalid pipe names are rejected", {
  expect_error(winpipe:::cpp_np_conn_exists(rawToChar(as.raw(0xff))))
})


test_that("only servers can listen and disconnect", {
  srv <- winpipe("test")
  cli <- winpipe("test")
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)
  expect_error(np_listen(cli), "server")
  expect_error(np_disconnect(cli), "server")
})


test_that("server creation failures are reported", {
  expect_error(winpipe("test", sddl = "not an sddl"), "SDDL invalid")

  srv <- winpipe("test", max_instances = 1)
  on.exit(close(srv), add = TRUE)
  expect_error(winpipe("test", server = TRUE), "CreateNamedPipe failed")
})


test_that("clients cannot open pipes that do not exist", {
  expect_error(winpipe("test", server = FALSE), "cannot find")
  expect_error(winpipe("test", server = FALSE, blocking = TRUE), "cannot find")
})


test_that("blocking servers time out waiting for a client", {
  expect_error(
    winpipe("test", server = TRUE, blocking = TRUE, timeout = 0.3),
    "Timed out .* waiting for a client"
  )
  expect_false(np_exists("test"))
})


test_that("np_listen times out without a client", {
  srv <- winpipe("test", timeout = 0.3)
  on.exit(close(srv), add = TRUE)
  expect_error(np_listen(srv), "Timed out .* waiting for a client")
})


test_that("clients time out waiting for a free instance", {
  srv <- winpipe("test", max_instances = 1)
  cli <- winpipe("test")
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)

  expect_error(
    winpipe("test", server = FALSE, blocking = TRUE, timeout = 0.3),
    "Timed out .* free pipe instance"
  )
  expect_error(winpipe("test", server = FALSE, blocking = FALSE), "busy|All pipe")
})


test_that("blocking reads time out", {
  srv <- winpipe("test", open = "r+b")
  cli <- winpipe("test", server = FALSE, open = "r+b", blocking = TRUE, timeout = 0.3)
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)

  expect_error(readBin(cli, "raw", 1), "Pipe read timed out")

  writeBin(as.raw(1:3), srv)
  expect_error(readBin(cli, "raw", 10), "3 of 10 bytes read")
})


test_that("blocking line reads time out", {
  srv <- winpipe("test")
  cli <- winpipe("test", server = FALSE, blocking = TRUE, timeout = 0.3)
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)

  expect_error(readLines(cli, n = 1), "Pipe read timed out")
})


test_that("writes time out when nobody reads", {
  srv <- winpipe("test", open = "r+b", timeout = 0.3)
  cli <- winpipe("test", server = FALSE, open = "r+b")
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)

  expect_error(
    writeBin(raw(4 * 2^20), srv),
    "Pipe write timed out"
  )
})


test_that("reading and writing after the peer closes", {
  srv <- winpipe("test", open = "r+b")
  cli <- winpipe("test", server = FALSE, open = "r+b")
  on.exit(close(srv), add = TRUE)

  writeBin(as.raw(1:3), cli)
  close(cli)

  expect_equal(readBin(srv, "raw", 10), as.raw(1:3))
  expect_length(readBin(srv, "raw", 10), 0)
  expect_error(writeBin(as.raw(1), srv))
})


test_that("line reads see EOF after the peer closes", {
  srv <- winpipe("test")
  cli <- winpipe("test", server = FALSE)
  on.exit(close(srv), add = TRUE)

  writeLines("bye", cli)
  close(cli)
  expect_equal(readLines(srv), "bye")
  expect_length(readLines(srv), 0)
})


test_that("blocking line reads see EOF after the peer closes", {
  srv <- winpipe("test")
  cli <- winpipe("test", server = FALSE, blocking = TRUE)
  on.exit(close(cli), add = TRUE)

  writeLines("bye", srv)
  expect_equal(readLines(cli, n = 1), "bye")
  close(srv)
  expect_length(readLines(cli), 0)
})


test_that("np_state reports blocking mode", {
  srv <- winpipe("test")
  on.exit(close(srv), add = TRUE)
  expect_equal(np_state(srv)$state, "blocking byte-mode")
})
