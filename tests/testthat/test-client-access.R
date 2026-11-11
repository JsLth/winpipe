test_that("write-only client can connect to a one-way inbound pipe", {
  skip_if_not_installed("processx")

  reader <- processx::conn_create_fifo()
  on.exit(close(reader), add = TRUE)
  name <- sub("^\\\\\\\\[.?]\\\\pipe\\\\", "", processx::conn_file_name(reader))

  expect_error(winpipe(name, open = "r+", server = FALSE), "error 5")

  client <- winpipe(name, open = "w", server = FALSE)
  on.exit(close(client), add = TRUE)
  writeLines("hello", client)

  expect_equal(processx::poll(list(reader), 2000)[[1]], "ready")
  expect_equal(processx::conn_read_lines(reader, 1), "hello")
})
