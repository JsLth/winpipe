#' Low-level information about a named pipe
#' @description
#' Functions to retrieve low-level information about a named pipe.
#' @param con \code{[winpipe]}.
#' 
#' An open \code{winpipe} as created by \code{\link{winpipe}}.
#' @returns \code{np_info} returns a list with the pipe role (server or client),
#' pipe type, buffer sizes, and maximum number of instances. \code{np_state}
#' returns a list with the raw handle state flags, the current number of
#' instances, and the name of the connected client (\code{NA} unless the handle
#' is a server with a connected client).
#' @rdname info
#' @export
np_info <- function(con) {
  check_winpipe(con)
  cpp_np_conn_info(con)
}


#' @rdname info
#' @export
np_state <- function(con) {
  check_winpipe(con)
  cpp_np_conn_state(con)
}


np_peek <- function(con) {
  check_winpipe(con)
  cpp_np_conn_peek(con)
}