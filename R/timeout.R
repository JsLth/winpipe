#' Named pipe timeouts
#' 
#' @description
#' Get or set the I/O timeout of a pipe connection
#'
#' @inheritParams np_config
#' @param timeout \code{[numeric]}
#' 
#' New timeout in seconds. Can be \code{Inf} to wait forever.
#' @return \code{np_get_timeout} returns the current timeout of
#' a \code{winpipe}. \code{np_set_timeout} returns the previous
#' timeout before setting.
#' @export
#' @rdname timeout
#' 
#' @examples
#' np <- winpipe("test")
#' on.exit(close(np))
#' 
#' np_get_timeout(np)
#' np_set_timeout(np, Inf)
#' np_get_timeout(np)
np_set_timeout <- function(con, timeout) {
  check_winpipe(con)
  invisible(cpp_np_conn_timeout(con, as.double(timeout), TRUE))
}


#' @rdname timeout
#' @export
np_get_timeout <- function(con) {
  check_winpipe(con)
  cpp_np_conn_timeout(con, 0, FALSE)
}