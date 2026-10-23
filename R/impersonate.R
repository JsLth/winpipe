#' Impersonation
#' 
#' @description
#' Impersonate a client (and revert). When impersonated,
#' pipe actions can be executed from the client's perspective.
#' 
#' Currently, there's no real use for these functions. You can
#' retrieve the name of the client using \code{\link{np_state}}.
#' 
#' After impersonating, make sure to always revert.
#' 
#' @inheritParams np_config
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

#' @rdname np_impersonate
#' @export
np_revert <- function() {
  cpp_np_revert()
}
