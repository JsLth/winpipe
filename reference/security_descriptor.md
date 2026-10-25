# Build, parse and inspect security descriptors

Security descriptors specify who can read or write a Windows object such
as a named pipe. They can be passed to
[`winpipe()`](https://jslth.github.io/winpipe/reference/winpipe.md).

A security descriptor has an owner, a primary group, a DACL (who may
access the pipe) and a SACL (auditing and integrity labels). These
functions let you construct and convert it to and from an SDDL string.

- `sd_new()` creates a security descriptor.

- `sd_add()` appends one or more
  [`ace()`](https://jslth.github.io/winpipe/reference/ace.md)s to the
  DACL or SACL, creating the ACL.

- `sd_build()` turns a descriptor into an SDDL string.

- `sd_parse()` turns an SDDL string into a descriptor.

- `sd_default()` returns the default DACL of the current token.

## Usage

``` r
sd_create(..., owner = NULL, group = NULL, dacl = NULL, sacl = NULL)

sd_add(sd, ..., acl = c("dacl", "sacl"))

sd_build(sd)

sd_parse(sddl)

sd_default()
```

## Arguments

- ...:

  One or more
  [`ace()`](https://jslth.github.io/winpipe/reference/ace.md) objects.

- owner, group:

  `[character(1)]`

  Owner and primary group, as an alias, description or SID. If `NULL`,
  does not specify an owner or a group.

- dacl, sacl:

  `[list]`

  Optional ACL, a list with `flags` and `aces`.

- sd:

  `[winpipe_sd]`

  A security descriptor as created by `sd_create()`.

- acl:

  `[character(1)]`

  Type of ACL to add to the security descriptor. Can be `"dacl"` or
  `"sacl"`.

- sddl:

  `[character(1)]`

  An SDDL string.

## Value

`sd_new()`, `sd_add()`, and `sd_parse()` return a `"winpipe_sd"` list.
`sd_build()` and `sd_default()` return

## Details

A parsed descriptor is a list with elements `owner`, `group`, `dacl`,
and `sacl`. Written as a string, a descriptor looks like this:

    O:BAG:WDD:(A;IO;GRGW;;;SY)

The prefix specifies the owner, primary group and DACL. Wrapped inside
brackets are the individual
[`ace`](https://jslth.github.io/winpipe/reference/ace.md)s, which
specify the DACL configurations. Multiple ACEs can follow each other.

Each ACE is a list with `type`, `flags`, `rights`, `object_guid`,
`inherit`, `account` and `extra`. A `NULL` DACL means the section is
absent, whereas an empty one (`flags` and `aces` both empty) grants
nobody access.

## Examples

``` r
x <- sd_new(owner = "admins") |>
  sd_add(ace(rights = "generic all", account = "local system")) |>
  sd_add(ace(rights = c("GR", "GW"), account = "authenticated users"))
#> Error in sd_new(owner = "admins"): could not find function "sd_new"
x
#> Error: object 'x' not found
sd_build(x)
#> Error: object 'x' not found

identical(sd_build(sd_parse(sd_default())), sd_default())
#> Error in sd_parse(sd_default()): Argument `sddl` must be a single string.
```
