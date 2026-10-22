#' Create an access control entry
#'
#' @description
#' Builds a single ACE for use with \code{\link{sd_add()}}. Types, flags, rights and
#' well-known accounts can be given either as their SDDL abbreviation (e.g.
#' `"GA"`) or by description (e.g. `"generic all"`). See details for lookup tables.
#'
#' @param type \code{[character(1)]}
#' 
#' ACE type. Defaults to `"allow"`.
#' @param flags \code{[character]}
#' 
#' ACE flags, e.g. \code{c("CI", "OI")}.
#' @param rights \code{[character]}
#' 
#' Access rights, e.g. \code{c("GR", "GW")}.
#' @param object_guid,inherit \code{[character(1)]}
#' 
#' Optional object GUIDs for object-specific ACE types.
#' @param account \code{[character(1)]}
#' 
#' An alias, description or SID of a trusted account.
#'
#' @return A list of class `"winpipe_ace"`.
#' 
#' @details
#' The following codes and descriptions can be used interchangeably for ACE components:
#' 
#' \strong{\code{type}:}
#' `r tabular(data.frame(Code = names(ace_types), Description = unlist(ace_types)))`
#' 
#' \strong{\code{flags}:}
#' `r tabular(data.frame(Code = names(ace_flags), Description = unlist(ace_flags)))`
#' 
#' \strong{\code{rights}:}
#' `r tabular(data.frame(Code = names(ace_rights), Description = unlist(ace_rights)))`
#' 
#' \strong{\code{account}:}
#' `r tabular(data.frame(Code = names(ace_accounts), Description = unlist(ace_accounts)))`
#' 
#' @export
#' 
#' @examples
#' # codes are allowed
#' ace("A", rights = "GA", account = "SY")
#' 
#' # as well as generic descriptions
#' ace("allow", rights = "generic all", account = "local system")
ace <- function(type = "allow",
                flags = NULL,
                rights = NULL,
                object_guid = NULL,
                inherit = NULL,
                account = NULL) {
  if (!is_string(type)) {
    stop("Argument `type` must be a single string.")
  }

  if (is.null(rights) || !is.character(rights)) {
    stop("Argument `rights` must be a character vector.")
  }

  if (!is_string(account)) {
    stop("Argument `account` must be a single string.")
  }

  if (!is.null(flags) && !is.character(flags)) {
    stop("Argument `flags` must be a character vector.")
  }

  if (!is.null(object_guid) && !is_string(object_guid)) {
    stop("Argument `object_guid` must be a single string.")
  }

  if (!is.null(inherit) && !is_string(inherit)) {
    stop("Argument `inherit` must be a single string.")
  }

  structure(
    list(
      type = resolve_token(type, ace_types, "ACE type"),
      flags = resolve_token(flags, ace_flags, "ACE flag"),
      rights = resolve_token(rights, ace_rights, "access right", hex = TRUE),
      object_guid = if (is.null(object_guid)) "" else object_guid,
      inherit_object_guid = if (is.null(inherit)) "" else inherit,
      account = resolve_account(account),
      extra = ""
    ),
    class = "winpipe_ace"
  )
}


#' @export
format.winpipe_ace <- function(x, ...) {
  fields <- c(
    x$type,
    paste(x$flags, collapse = ""),
    paste(x$rights, collapse = ""),
    x$object_guid,
    x$inherit_object_guid,
    x$account
  )
  if (nzchar(x$extra)) fields <- c(fields, x$extra)
  paste0("(", paste(fields, collapse = ";"), ")")
}


#' @export
print.winpipe_ace <- function(x, ...) {
  cat("<winpipe_ace> ", format(x), "\n", sep = "")
  invisible(x)
}


#' Helper function to match a SDDL token to a list of
#' known tokens.
#' @noRd 
resolve_token <- function(x, table, what, hex = FALSE) {
  vapply(x, function(v) {
    if (v %in% names(table)) {
      return(v)
    }
    idx <- match(v, unlist(table))
    if (!is.na(idx)) {
      return(names(table)[idx])
    }
    if (hex && grepl("^0x[0-9a-fA-F]+$", v)) {
      return(v)
    }
    stop(sprintf("'%s' is an unknown %s.", v, what), call. = FALSE)
  }, character(1), USE.NAMES = FALSE)
}


#' Helper function to match account SID to a well-known one.
#' If no SID is matched, return as-is.
#' @noRd
resolve_account <- function(x) {
  idx <- match(x, unlist(ace_accounts))
  if (is.na(idx)) x else names(ace_accounts)[idx]
}


ace_types <- list(
  A = "allow",
  D = "denied",
  OA = "object-specific access allowed",
  OD = "object-specific access denied",
  AU = "system audit",
  AL = "system alarm",
  OU = "object-specific system audit",
  ML = "mandatory label"
)


ace_flags <- list(
  OI = "object inherit",
  CI = "container inherit",
  NP = "no propagate inherit",
  IO = "inherit only",
  ID = "inherited ACE",
  SA = "successful access audit",
  FA = "failed access audit"
)


ace_rights <- list(
  GA = "generic all",
  GR = "generic read",
  GW = "generic write",
  GX = "generic execute",
  FA = "file all access",
  FR = "file generic read",
  FW = "file generic write",
  FX = "file generic execute",
  KA = "key all access",
  KR = "key read",
  KW = "key write",
  KX = "key execute",
  RP = "read property",
  WP = "write property",
  WD = "modify permissions",
  RC = "read control",
  SD = "delete",
  WO = "change owner",
  NW = "no write up",
  NR = "no read up",
  NX = "no execute up"
)


ace_accounts <- list(
  BA = "admins",
  WD = "everyone",
  SY = "local system",
  AU = "authenticated users",
  LS = "local service",
  NS = "network service",
  AN = "anonymous",
  IU = "interactive users",
  CO = "creator owner",
  CG = "creator group",
  AC = "all application packages",
  LW = "low integrity",
  ME = "medium integrity",
  HI = "high integrity",
  SI = "system integrity"
)
