test_that("check_installed() errors for missing packages", {
  expect_silent(check_installed("stats"))
  expect_error(
    check_installed("notapackage123", "do something"),
    "required to do something"
  )
  expect_error(check_installed("notapackage123"), "`notapackage123` required\\.")
  expect_true(is_installed("stats"))
  expect_false(is_installed("notapackage123"))
})
