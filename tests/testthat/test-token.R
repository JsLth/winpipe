test_that("token info of the own process is returned", {
  info <- np_token_info()
  expect_named(
    info,
    c("user", "sid", "groups", "elevated", "integrity", "token_type",
      "impersonation_level")
  )
  expect_match(info$user, "\\\\")
  expect_match(info$sid, "^S-1-")
  expect_s3_class(info$groups, "data.frame")
  expect_named(info$groups, c("name", "sid", "enabled"))
  expect_equal(info$token_type, "primary")
  expect_true(is.na(info$impersonation_level))
  expect_true(info$integrity %in% c("low", "medium", "high", "system"))
  expect_equal(np_whoami(), info$user)
})


test_that("token info of a pipe client is returned", {
  srv <- winpipe("test")
  cli <- winpipe("test")
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)

  info <- np_token_info(srv)
  expect_equal(info$token_type, "impersonation")
  expect_equal(info$impersonation_level, "identification")
  expect_equal(info$sid, np_token_info()$sid)
  expect_type(np_whoami(srv), "character")
})


test_that("token info validates its input", {
  expect_error(np_token_info("test"), "winpipe")

  srv <- winpipe("test")
  cli <- winpipe("test")
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)
  expect_error(np_token_info(cli), "server end")
})


test_that("token info of a server without client fails", {
  srv <- winpipe("test")
  on.exit(close(srv), add = TRUE)
  expect_error(np_token_info(srv), "ImpersonateNamedPipeClient")
})
