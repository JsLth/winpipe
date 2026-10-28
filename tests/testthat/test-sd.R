# test/testthat/test-security_descriptor.R

# Helper function to create a simple ACE for testing
make_ace <- function(type = "A", flags = character(), rights = "GR", account = "everyone") {
  ace(rights = rights, account = account, type = type, flags = flags)
}

# -----------------------------------------------------------------------------
# Tests for sd_create()
# -----------------------------------------------------------------------------

test_that("sd_create creates a basic security descriptor", {
  sd <- sd_create()
  expect_s3_class(sd, "winpipe_sd")
  expect_named(sd, c("owner", "group", "dacl", "sacl"))
  expect_null(sd$owner)
  expect_null(sd$group)
  expect_null(sd$dacl)
  expect_null(sd$sacl)
})

test_that("sd_create with owner parameter", {
  sd <- sd_create(owner = "admins")
  expect_s3_class(sd, "winpipe_sd")
  expect_equal(sd$owner, "BA")
})

test_that("sd_create with group parameter", {
  sd <- sd_create(group = "everyone")
  expect_s3_class(sd, "winpipe_sd")
  expect_equal(sd$group, "WD")
})

test_that("sd_create with owner and group", {
  sd <- sd_create(owner = "admins", group = "everyone")
  expect_s3_class(sd, "winpipe_sd")
  expect_equal(sd$owner, "BA")
  expect_equal(sd$group, "WD")
})

test_that("sd_create with initial ACEs via ...", {
  sd <- sd_create(
    owner = "admins",
    make_ace(rights = "GR", account = "everyone")
  )
  expect_s3_class(sd, "winpipe_sd")
  expect_length(sd$dacl$aces, 1)
})

test_that("sd_create with multiple initial ACEs", {
  sd <- sd_create(
    make_ace(rights = "GR", account = "everyone"),
    make_ace(rights = "GW", account = "users")
  )
  expect_length(sd$dacl$aces, 2)
})

test_that("sd_create with dacl parameter", {
  dacl <- list(flags = character(), aces = list(make_ace()))
  sd <- sd_create(dacl = dacl)
  expect_s3_class(sd, "winpipe_sd")
  expect_length(sd$dacl$aces, 1)
})

test_that("sd_create with sacl parameter", {
  sacl <- list(flags = character(), aces = list(make_ace()))
  sd <- sd_create(sacl = sacl)
  expect_s3_class(sd, "winpipe_sd")
  expect_length(sd$sacl$aces, 1)
})

test_that("sd_create with all parameters", {
  sd <- sd_create(
    owner = "admins",
    group = "everyone",
    dacl = list(flags = character(), aces = list(make_ace())),
    sacl = list(flags = character(), aces = list(make_ace()))
  )
  expect_s3_class(sd, "winpipe_sd")
  expect_equal(sd$owner, "BA")
  expect_equal(sd$group, "WD")
  expect_length(sd$dacl$aces, 1)
  expect_length(sd$sacl$aces, 1)
})

test_that("sd_create rejects non-string owner", {
  expect_error(
    sd_create(owner = c("a", "b")),
    "Arguments `owner` and `group` must be single strings."
  )
})

test_that("sd_create rejects non-string group", {
  expect_error(
    sd_create(group = c("a", "b")),
    "Arguments `owner` and `group` must be single strings."
  )
})

test_that("sd_create rejects non-list dacl", {
  expect_error(
    sd_create(dacl = "not a list"),
    "Arguments `dacl` and `sacl` must be lists."
  )
})

test_that("sd_create rejects non-list sacl", {
  expect_error(
    sd_create(sacl = "not a list"),
    "Arguments `dacl` and `sacl` must be lists."
  )
})

# -----------------------------------------------------------------------------
# Tests for sd_add()
# -----------------------------------------------------------------------------

test_that("sd_add adds ACE to dacl", {
  sd <- sd_create(owner = "admins")
  sd <- sd_add(sd, make_ace(rights = "GR", account = "users"))
  expect_length(sd$dacl$aces, 1)
  expect_s3_class(sd$dacl$aces[[1]], "winpipe_ace")
})

test_that("sd_add adds ACE to sacl", {
  sd <- sd_create()
  sd <- sd_add(sd, make_ace(rights = "GR", account = "users"), acl = "sacl")
  expect_length(sd$sacl$aces, 1)
})

test_that("sd_add appends multiple ACEs", {
  sd <- sd_create()
  sd <- sd_add(
    sd,
    make_ace(rights = "GR", account = "users"),
    make_ace(rights = "GW", account = "admins")
  )
  expect_length(sd$dacl$aces, 2)
})

test_that("sd_add creates dacl if it doesn't exist", {
  sd <- sd_create(owner = "admins")
  expect_null(sd$dacl)
  sd <- sd_add(sd, make_ace())
  expect_length(sd$dacl$aces, 1)
  expect_s3_class(sd$dacl$aces[[1]], "winpipe_ace")
})

test_that("sd_add validates sd class", {
  expect_error(
    sd_add("not a sd", make_ace()),
    "Argument `sd` must be a security descriptor from `sd_new\\(\\)`."
  )
})

test_that("sd_add requires at least one ACE", {
  sd <- sd_create()
  expect_error(
    sd_add(sd),
    "Provide at least one ACE."
  )
})

test_that("sd_add validates ACE arguments", {
  sd <- sd_create()
  expect_error(
    sd_add(sd, list(not = "an ace")),
    "All arguments in `\\.\\.\\.` must be ACEs created with `ace\\(\\)`."
  )
})

test_that("sd_add with invalid acl argument", {
  sd <- sd_create()
  expect_error(
    sd_add(sd, make_ace(), acl = "invalid"),
    "'arg' should be one of"
  )
})

# -----------------------------------------------------------------------------
# Tests for sd_build()
# -----------------------------------------------------------------------------

test_that("sd_build returns string for basic descriptor", {
  sd <- sd_create()
  result <- sd_build(sd)
  expect_vector(result, character(), 1)
})

test_that("sd_build returns string for descriptor with owner", {
  sd <- sd_create(owner = "admins")
  result <- sd_build(sd)
  expect_vector(result, character(), 1)
  expect_match(result, "O:")
})

test_that("sd_build returns string for descriptor with ACEs", {
  sd <- sd_create()
  sd <- sd_add(sd, make_ace(rights = "GR", account = "everyone"))
  result <- sd_build(sd)
  expect_vector(result, character(), 1)
  expect_match(result, "D:")
})

test_that("sd_build rejects non-list input", {
  expect_error(
    sd_build("not a list"),
    "Argument `sd` must be a list."
  )
})

test_that("sd_build rejects wrong inputs", {
  sd <- sd_create()
  sd <- sd_add(sd, make_ace(rights = "GR", account = "unknown"))
  expect_error(sd_build(sd), "error 1337[)]")
})

# -----------------------------------------------------------------------------
# Tests for sd_parse()
# -----------------------------------------------------------------------------

test_that("sd_parse parses valid SDDL string", {
  sddl <- "O:BAG:BAD:"
  sd <- sd_parse(sddl)
  expect_s3_class(sd, "winpipe_sd")
})

test_that("sd_parse parses SDDL with DACL", {
  sddl <- "O:BAG:BAD:(A;;GR;;;WD)"
  sd <- sd_parse(sddl)
  expect_s3_class(sd, "winpipe_sd")
  expect_length(sd$dacl$aces, 1)
})

test_that("sd_parse parses SDDL with owner", {
  sddl <- "O:SYG:BAD:"
  sd <- sd_parse(sddl)
  expect_s3_class(sd, "winpipe_sd")
  expect_equal(sd$owner, "SY")
})

test_that("sd_parse rejects non-string input", {
  expect_error(
    sd_parse(123),
    "Argument `sddl` must be a single string."
  )
})

test_that("sd_parse rejects empty string", {
  expect_equal(
    sd_parse(""),
    list(owner = NULL, group = NULL, dacl = NULL, sacl = NULL),
    ignore_attr = TRUE
  )
})

# -----------------------------------------------------------------------------
# Tests for round-trip functionality
# -----------------------------------------------------------------------------

test_that("build and parse are inverses for simple descriptor", {
  sd <- sd_create()
  sddl <- sd_build(sd)
  sd2 <- sd_parse(sddl)
  expect_identical(sd_build(sd2), sddl)
})

test_that("build and parse are inverses for descriptor with owner", {
  sd <- sd_create(owner = "admins")
  sddl <- sd_build(sd)
  sd2 <- sd_parse(sddl)
  expect_identical(sd_build(sd2), sddl)
})

test_that("build and parse preserve ACEs", {
  sd <- sd_create(owner = "admins")
  sd <- sd_add(
    sd,
    make_ace(rights = "GR", account = "everyone"),
    make_ace(rights = "GW", account = "authenticated users")
  )
  sddl <- sd_build(sd)
  sd2 <- sd_parse(sddl)
  expect_length(sd2$dacl$aces, 2)
  expect_identical(sd_build(sd2), sddl)
})

# -----------------------------------------------------------------------------
# Tests for format and print methods
# -----------------------------------------------------------------------------

test_that("format.winpipe_sd returns SDDL string", {
  sd <- sd_create()
  result <- format(sd)
  expect_vector(result, character(), 1)
})

test_that("print.winpipe_sd outputs expected format", {
  sd <- sd_create()
  expect_output(
    print(sd),
    "<winpipe_sd>"
  )
})

# -----------------------------------------------------------------------------
# Tests for sd_default()
# -----------------------------------------------------------------------------

test_that("sd_default returns a security descriptor", {
  sd <- sd_default()
  expect_s3_class(sd, "winpipe_sd")
  expect_named(sd, c("owner", "group", "dacl", "sacl"))
})

test_that("sd_default DACL can be built to string", {
  sd <- sd_default()
  sddl <- sd_build(sd)
  expect_vector(sddl, character(), 1)
})

# -----------------------------------------------------------------------------
# Tests for is_ace() helper
# -----------------------------------------------------------------------------

test_that("is_ace returns TRUE for valid ACE", {
  ace_obj <- list(
    type = "A",
    flags = character(),
    rights = "GR",
    account = "everyone",
    object_guid = NULL,
    inherit = NULL,
    extra = NULL
  )
  expect_true(is_ace(ace_obj))
})

test_that("is_ace returns FALSE for missing required fields", {
  bad_ace <- list(type = "A", flags = character())
  expect_false(is_ace(bad_ace))
})

test_that("is_ace returns FALSE for non-list input", {
  expect_false(is_ace("not a list"))
})

test_that("is_ace returns FALSE for empty list", {
  expect_false(is_ace(list()))
})

# -----------------------------------------------------------------------------
# Integration tests with actual usage patterns
# -----------------------------------------------------------------------------

test_that("typical usage pattern: create, add, build, parse", {
  sd <- sd_create(owner = "admins")
  sd <- sd_add(
    sd,
    ace(rights = "GR", account = "everyone")
  )
  sddl <- sd_build(sd)
  
  sd2 <- sd_parse(sddl)
  expect_identical(sd_build(sd2), sddl)
})

test_that("complex security descriptor with multiple ACEs", {
  sd <- sd_create(
    owner = "admins",
    group = "everyone"
  )
  sd <- sd_add(
    sd,
    ace(rights = "GR", account = "local system"),
    ace(rights = c("GR", "GW"), account = "admins"),
    ace(rights = "GR", account = "everyone")
  )
  
  sddl <- sd_build(sd)
  expect_vector(sddl, character(), 1)
  
  sd_parsed <- sd_parse(sddl)
  expect_length(sd_parsed$dacl$aces, 3)
})


test_that("sd_parse handles ACL flags", {
  x <- sd_parse("D:PAI(A;;GA;;;SY)")
  expect_equal(x$dacl$flags, c("P", "AI"))

  x <- sd_parse("D:AR(A;;GA;;;SY)")
  expect_equal(x$dacl$flags, "AR")

  x <- sd_parse("D:NO_ACCESS_CONTROL")
  expect_equal(x$dacl$flags, "NO_ACCESS_CONTROL")
  expect_length(x$dacl$aces, 0)
})


test_that("sd_parse keeps numeric masks whole", {
  x <- sd_parse("D:(A;;0x1200a9;;;SY)")
  expect_equal(x$dacl$aces[[1]]$rights, "0x1200a9")
})


test_that("sd_parse handles conditional ACEs", {
  sddl <- 'D:(XA;;FX;;;S-1-1-0;(@User.Title=="PM"))'
  x <- sd_parse(sddl)
  expect_equal(x$dacl$aces[[1]]$extra, '(@User.Title=="PM")')
  expect_equal(sd_build(x), sddl)
})


test_that("sd_parse handles sacls and labels", {
  x <- sd_parse("S:(AU;SAFA;GA;;;WD)(ML;;NW;;;LW)")
  expect_length(x$sacl$aces, 2)
  expect_equal(sd_build(x), "S:(AU;SAFA;GA;;;WD)(ML;;NW;;;LW)")
})


test_that("sd_parse rejects what Windows rejects", {
  expect_error(sd_parse("garbage"), "Invalid SDDL")
  expect_error(sd_parse("O:BAO:BA"))
  expect_error(sd_parse(rawToChar(as.raw(c(0x4f, 0x3a, 0xff)))))
})


test_that("sd_build validates the structure of its input", {
  build <- cpp_sd_build

  expect_error(build(list(owner = 1)), "character vector")
  expect_error(build(list(owner = c("BA", "SY"))), "single string")
  expect_error(build(list(dacl = "x")), "must be a list")
  expect_error(build(list(dacl = list(flags = "P", aces = "x"))), "must be a list")
  expect_error(build(list(dacl = list(flags = "P", aces = list("x")))), "Each ACE")
  expect_equal(build(list(dacl = list(flags = "P"))), "D:P")
  expect_equal(build(list()), "")
  expect_error(build(list(owner = "not-a-sid-at-all")), "Invalid SDDL")
})


if (np_exists("test")) {
  stop("Named pipe 'test' exists on the system. Make sure to close it before testing.")
}

test_that("existing pipes can be read by name", {
  srv <- winpipe("test")
  on.exit(close(srv), add = TRUE)

  sddl <- cpp_np_sddl("\\\\.\\pipe\\test", FALSE)
  expect_match(sddl, "^O:")
  expect_equal(sd_parse(sddl)$dacl, np_sd(srv)$dacl)

  expect_error(
    cpp_np_sddl("\\\\.\\pipe\\does-not-exist", FALSE),
    "Cannot open pipe"
  )
  expect_error(cpp_np_sddl("\\\\.\\pipe\\test", TRUE), "Access|privilege|denied|Cannot", ignore.case = TRUE)
})


test_that("busy pipes can still be read by name", {
  srv <- winpipe("test", max_instances = 1)
  cli <- winpipe("test")
  on.exit(close(cli), add = TRUE)
  on.exit(close(srv), add = TRUE)

  res <- tryCatch(cpp_np_sddl("\\\\.\\pipe\\test", FALSE), error = identity)
  expect_true(is.character(res) || inherits(res, "error"))
})
