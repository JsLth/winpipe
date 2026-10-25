#' Build, parse and inspect security descriptors
#'
#' @description
#' Security descriptors specify who can read or write a Windows object
#' such as a named pipe. They can be passed to [winpipe()].
#' 
#' A security descriptor has an owner, a primary group, a DACL (who may access
#' the pipe) and a SACL (auditing and integrity labels). These functions let
#' you construct and convert it to and from an SDDL string.
#'
#' * \code{sd_new()} creates a security descriptor.
#' * \code{sd_add()} appends one or more [ace()]s to the DACL or SACL, creating
#'   the ACL.
#' * \code{sd_build()} turns a descriptor into an SDDL string.
#' * \code{sd_parse()} turns an SDDL string into a descriptor.
#' * \code{sd_default()} returns the default DACL of the current token.
#' 
#' @param owner,group \code{[character(1)]}
#' 
#' Owner and primary group, as an alias, description or SID. If \code{NULL},
#' does not specify an owner or a group.
#' @param dacl,sacl \code{[list]}
#' 
#' Optional ACL, a list with `flags` and `aces`.
#' @param sd \code{[winpipe_sd]}
#' 
#' A security descriptor as created by \code{sd_create()}.
#' @param ... One or more [ace()] objects.
#' @param acl \code{[character(1)]}
#' 
#' Type of ACL to add to the security descriptor. Can be \code{"dacl"}
#' or \code{"sacl"}.
#' @param sddl \code{[character(1)]}
#' 
#' An SDDL string.
#'
#' @returns \code{sd_new()}, \code{sd_add()}, and \code{sd_parse()} return a
#' \code{"winpipe_sd"} list. \code{sd_build()} and \code{sd_default()} return
#' 
#' @details
#' A parsed descriptor is a list with elements \code{owner}, \code{group},
#' \code{dacl}, and \code{sacl}. Written as a string, a descriptor looks like this:
#' 
#' \preformatted{O:BAG:WDD:(A;IO;GRGW;;;SY)}
#' 
#' The prefix specifies the owner, primary group and DACL. Wrapped inside brackets
#' are the individual \code{\link{ace}}s, which specify the DACL configurations.
#' Multiple ACEs can follow each other.
#' 
#' Each ACE is a list with \code{type}, \code{flags}, \code{rights}, \code{object_guid},
#' \code{inherit}, \code{account} and \code{extra}. A \code{NULL} DACL means the
#' section is absent, whereas an empty one (`flags` and `aces` both empty)
#' grants nobody access.
#'
#' @examples
#' x <- sd_new(owner = "admins") |>
#'   sd_add(ace(rights = "generic all", account = "local system")) |>
#'   sd_add(ace(rights = c("GR", "GW"), account = "authenticated users"))
#' x
#' sd_build(x)
#'
#' identical(sd_build(sd_parse(sd_default())), sd_default())
#' @name security_descriptor
NULL

#' @rdname security_descriptor
#' @export
sd_create <- function(..., owner = NULL, group = NULL, dacl = NULL, sacl = NULL) {
  for (arg in list(owner = owner, group = group)) {
    if (!is.null(arg) && !is_string(arg)) {
      stop("Arguments `owner` and `group` must be single strings.")
    }
  }
  for (arg in list(dacl = dacl, sacl = sacl)) {
    if (!is.null(arg) && !is.list(arg)) {
      stop("Arguments `dacl` and `sacl` must be lists.")
    }
  }

  sd <- new_sd(
    owner = if (is.null(owner)) NULL else resolve_account(owner),
    group = if (is.null(group)) NULL else resolve_account(group),
    dacl = dacl,
    sacl = sacl
  )

  if (...length()) {
    sd <- sd_add(sd, ...)
  }

  sd
}

#' @rdname security_descriptor
#' @export
sd_add <- function(sd, ..., acl = c("dacl", "sacl")) {
  if (!inherits(sd, "winpipe_sd")) {
    stop("Argument `sd` must be a security descriptor from `sd_new()`.")
  }
  acl <- match.arg(acl)

  aces <- list(...)
  if (length(aces) == 0L) {
    stop("Provide at least one ACE.")
  }
  ok <- vapply(aces, is_ace, logical(1))
  if (!all(ok)) {
    stop("All arguments in `...` must be ACEs created with `ace()`.")
  }

  current <- sd[[acl]]
  if (is.null(current)) {
    current <- list(flags = character(), aces = list())
  }
  current$aces <- c(current$aces, aces)
  sd[[acl]] <- current
  sd
}

#' @rdname security_descriptor
#' @export
sd_build <- function(sd) {
  if (!is.list(sd)) {
    stop("Argument `sd` must be a list.")
  }
  cpp_sd_build(unclass(sd))
}

#' @rdname security_descriptor
#' @export
sd_parse <- function(sddl) {
  if (!is_string(sddl)) {
    stop("Argument `sddl` must be a single string.")
  }
  do.call(new_sd, cpp_sd_parse(sddl))
}

#' @rdname security_descriptor
#' @export
sd_default <- function() {
  sd_parse(cpp_default_dacl())
}


#' @export
format.winpipe_sd <- function(x, ...) {
  sd_build(x)
}

#' @export
print.winpipe_sd <- function(x, ...) {
  cat("<winpipe_sd>\n", sd_build(x), "\n", sep = "")
  invisible(x)
}


new_sd <- function(owner, group, dacl, sacl) {
  if (length(dacl)) dacl$aces <- lapply(dacl$aces, structure, class = "winpipe_ace")
  if (length(sacl)) sacl$aces <- lapply(sacl$aces, structure, class = "winpipe_ace")
  structure(
    list(owner = owner, group = group, dacl = dacl, sacl = sacl),
    class = "winpipe_sd"
  )
}


is_ace <- function(x) {
  is.list(x) &&
    all(c("type", "flags", "rights", "account") %in% names(x))
}
