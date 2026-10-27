#' Low-level information about a named pipe
#' 
#' @description
#' Functions to retrieve low-level information about a named pipe.
#' 
#' \itemize{
#'  \item{\code{np_config()} returns the pipe configuration.}
#'  \item{\code{np_state()} returns the current clients.}
#'  \item{\code{np_peek()} looks at the bytes of a pipe without reading.}
#'  \item{\code{np_sd()} returns the \link[=security_descriptor]{security descriptor}.}
#' }
#' 
#' @param con \code{[winpipe]}.
#' 
#' An open \code{winpipe} as created by \code{\link{winpipe}}.
#' 
#' @returns \code{np_config()} returns:
#' 
#' \itemize{
#'  \item{\code{is_server} and \code{is_client}}: Whether the pipe is started as a server or client.
#'  \item{\code{is_message_type} and \code{is_byte_type}: Whether the pipe reads data as bytes or messages. Pipes created using \code{winpipe} always read bytes.}
#' \item{\code{out_buffer_size} and \code{in_buffer_size}: Size of input and output chunks.}
#'  \item{\code{max_instances}: Maximum allowed instances.}
#' }
#' 
#' \code{np_state()} returns:
#' 
#' \itemize{
#'  \item{\code{state}: The reading mode of the pipe. Can be either blocking or non-blocking and byte-mode or message-mode. Pipes created using \code{winpipe} should always be in blocking byte-mode.}
#'  \item{\code{current_instances}: Number of instances related to a pipe.}
#'  \item{\code{username}: If \code{con} is a server, reports the username of the current client, if any. If \code{con} is a client, \code{NA}.}
#' }
#' 
#' \code{np_peek()} returns the number of bytes available to read from the pipe. If \code{np_peek()} cannot read from the pipe, returns the error code as a warning.
#' 
#' \code{np_sd()} returns an object of class \code{\link[=security_descriptor]{winpipe_sd}}.
#' @export
#' @rdname info
#' 
#' @examples
#' srv <- winpipe("test")
#' cli <- winpipe("test")
#' 
#' np_config(srv)
#' np_state(srv)
#' 
#' np_peek(srv)
#' writeLines("hello\nworld", cli)
#' np_peek(srv)
#' readLines(srv, n = 1)
#' np_peek(srv)
#' 
#' close(srv)
#' close(cli)
np_config <- function(con) {
  check_winpipe(con)
  cpp_np_conn_info(con)
}


#' @rdname info
#' @export
np_state <- function(con) {
  check_winpipe(con)
  out <- cpp_np_conn_state(con)
  out$state <- switch(
    as.character(out$state),
    `0` = "blocking byte-mode",
    `1` = "non-blocking byte-mode",
    `2` = "blocking message-mode",
    `3` = "non-blocking message-mode"
  )

  out
}


#' @rdname info
#' @export
np_peek <- function(con) {
  check_winpipe(con)
  out <- cpp_np_conn_peek(con)

  err <- out$error_code
  if (!is.na(err)) {
    warning(err, call. = FALSE)
  }

  out <- out$available
  out
}


#' @rdname info
#' @export
np_sd <- function(con) {
  check_winpipe(con)
  sd_parse(cpp_np_conn_sddl(con))
}