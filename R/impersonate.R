#' Impersonation
#' 
#' @description
#' Impersonate a client (and revert).
#' 
#' @inheritParams np_info
#' @returns Nothing.
#' 
#' @examples
#' server <- winpipe("test")
#' client <- winpipe("test")
#' np_impersonate()
#' on.exit(np_revert())
np_impersonate <- function(con) {
  cpp_np_conn_impersonate(con)
}

np_revert <- function() {
  cpp_np_revert()
}
