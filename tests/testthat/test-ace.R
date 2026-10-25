test_that("ace() validates its arguments", {
  expect_error(ace(type = 1, rights = "GA", account = "SY"), "`type`")
  expect_error(ace(type = c("A", "D"), rights = "GA", account = "SY"), "`type`")
  expect_error(ace(account = "SY"), "`rights`")
  expect_error(ace(rights = 1, account = "SY"), "`rights`")
  expect_error(ace(rights = "GA"), "`account`")
  expect_error(ace(rights = "GA", account = c("SY", "BA")), "`account`")
  expect_error(ace(rights = "GA", account = "SY", flags = 1), "`flags`")
  expect_error(ace(rights = "GA", account = "SY", object_guid = 1), "`object_guid`")
  expect_error(ace(rights = "GA", account = "SY", inherit = c("a", "b")), "`inherit`")
})


test_that("ace() resolves codes, descriptions and hex masks", {
  x <- ace("allow", flags = c("container inherit", "OI"),
           rights = c("generic read", "GW"), account = "local system")
  expect_equal(x$type, "A")
  expect_equal(x$flags, c("CI", "OI"))
  expect_equal(x$rights, c("GR", "GW"))
  expect_equal(x$account, "SY")

  expect_equal(ace(rights = "0x1200a9", account = "SY")$rights, "0x1200a9")
  expect_equal(ace(rights = "GA", account = "S-1-5-21-1")$account, "S-1-5-21-1")
})


test_that("ace() rejects unknown tokens", {
  expect_error(ace("nonsense", rights = "GA", account = "SY"), "unknown ACE type")
  expect_error(ace(flags = "zz", rights = "GA", account = "SY"), "unknown ACE flag")
  expect_error(ace(rights = "zz", account = "SY"), "unknown access right")
})


test_that("ace() keeps GUIDs and inherit GUIDs", {
  x <- ace("OA", rights = "RP", account = "SY",
           object_guid = "guid-1", inherit = "guid-2")
  expect_equal(x$object_guid, "guid-1")
  expect_equal(x$inherit_object_guid, "guid-2")
  expect_equal(format(x), "(OA;;RP;guid-1;guid-2;SY)")
})


test_that("winpipe_ace formats and prints", {
  x <- ace(flags = c("CI", "OI"), rights = c("GR", "GW"), account = "SY")
  expect_equal(format(x), "(A;CIOI;GRGW;;;SY)")
  expect_output(res <- print(x), "<winpipe_ace> \\(A;CIOI;GRGW;;;SY\\)")
  expect_identical(res, x)

  x$extra <- "extra"
  expect_equal(format(x), "(A;CIOI;GRGW;;;SY;extra)")
})
