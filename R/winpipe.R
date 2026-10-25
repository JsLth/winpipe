#' Named pipes
#' @description
#' Functions to create, open, and close named pipes on Windows.
#' 
#' \itemize{
#'  \item{\code{winpipe()} creates a new named pipe on Windows.}
#'  \item{\code{is_winpipe()} checks if an object is a winpipe.}
#'  \item{\code{np_listen()} blocks the session and listens to a pipe.}
#'  \item{\code{np_disconnect()} disconnects a client.}
#'  \item{\code{np_exists()} checks if a named pipe name exists.}
#'  \item{\code{np_list()} lists all named pipes currently on the machine.}
#' }
#'
#' @param name \code{[character(1)]}
#' 
#' Pipe name, with or without the `\\.\pipe\` prefix.
#' @param open \code{[character(1)]}
#' 
#' A description of how to open the connection. See \code{\link[base]{pipe}}.
#' @param server \code{[logical(1)]}
#' 
#' Whether the connection should be opened as a server or client. If
#'   \code{TRUE}, creates the pipe. If \code{FALSE}, only connects to it.
#'   Defaults to \code{TRUE} when no pipe with that can be found, otherwise
#'   \code{FALSE}.
#' @param blocking \code{[logical(1)]}
#' 
#' Whether the connection is blocking. See \code{\link[base]{open}}.
#'   For a server, a blocking open waits until a client connects (see
#'   \code{timeout}). A non-blocking open returns immediately and
#'   \code{np_listen()} can accept a client later. For reads, a blocking
#'   connection waits for data, while a non-blocking one returns only what is
#'   available (possibly nothing) and leaves a partial line for the next read.
#'   Writes always block. Defaults to \code{FALSE}.
#' @param sddl \code{[winpipe_sd]} or \code{[character(1)]}
#' 
#' Security descriptor string, or a security descriptor built with
#'   \code{\link{sd_create}}. Ignored if \code{server} is \code{FALSE}.
#'   Defaults to the default DACL of the current token (\code{\link{sd_default}}).
#' @param max_instances \code{[numeric(1)]}
#' 
#' Maximum allowed instances that can be opened on a named pipe. Can be a number
#'   between 1 and 254. If \code{Inf}, a maximum of 255 instances is allowed.
#'   `max_instances` is set on the creation of the pipe. This means that all
#'   connections connecting to an existing pipe cannot change the maximum number
#'   of instances. Defaults to \code{Inf}.
#' @param timeout \code{[numeric(1)]}
#' 
#' Seconds without progress before a read, write, accept, or open fails with
#'   an error. If \code{Inf}, waits forever. Defaults to \code{getOption("timeout")}.
#'   A read that times out after receiving bytes returns them with a warning instead of
#'   discarding them.
#' @param con \code{[winpipe]}
#' 
#' A \code{winpipe} connection created by \code{winpipe}.
#' @param ... Further arguments passed to \code{\link[base]{open}}.
#' @param x Any object.
#' @returns \code{named_pipe} returns a connection of class \code{"named_pipe"}.
#' All methods accepting a connection work on named pipes. Use \code{open = "r+b"} for
#' \code{\link{readBin}} and \code{\link{writeBin}}.
#' 
#' @details
#' Named pipes behave differently depending on whether they are initialized as a
#' server or client. When \code{server = TRUE}, \code{open()} creates the named
#' pipe so that a client can connect to it. With \code{blocking = TRUE} the
#' open waits for a client to connect; otherwise run \code{np_listen()} to block
#' the session until one does.
#' \code{np_disconnect()} drops the current client and discards all unread data.
#' \code{close()} destroys the instance but does not disconnect first, so data
#' already written stays readable by the client.
#' 
#' When \code{server = FALSE}, the named pipe cannot be created or destroyed.
#' Clients can only read or write but not change the state of the named pipe.
#' If a client named pipe is opened but there is no server instance available
#' to answer it, it will block the session until its timeout is reached or
#' an interrupt is signaled.
#' 
#' @section Blocking:
#' 
#' The principles of blocking are explained in \code{\link[base]{pipe}}.
#' Since \code{readLines()} with \code{n = -1} reads until the end of the
#' input, reading all lines from a server blocks the session until the
#' client signals the end of the input by closing the connection. 
#' 
#' 
#' @export
#' 
#' @examples
#' server <- winpipe("test")
#' client <- winpipe("test", server = FALSE)
#' 
#' # Nothing written yet
#' readLines(server)
#' 
#' # Client writes to pipe
#' cat("hello", file = client)
#' writeLines("world")
#' 
#' # Server can now receive the content
#' readLines(server)
#' 
#' close(client)
#' close(server)
winpipe <- function(name,
                    open = "r+",
                    server = !np_exists(name),
                    blocking = FALSE,
                    sddl = sd_default(),
                    max_instances = Inf,
                    timeout = getOption("timeout")) {
  if (!is_string(name)) {
    stop("`name` must be a single string.")
  }

  if (!(is_number(max_instances) && (max_instances >= 1 && max_instances <= 254)) &&
    !(is.infinite(max_instances))) {
    stop("`max_instances` must be `Inf` or a single number between 1 and 254.")
  }

  if (!is_number(timeout) || timeout < 0) {
    stop("`timeout` must be a single non-negative number.")
  }

  if (inherits(sddl, "winpipe_sd")) {
    sddl <- sd_build(sddl)
  }
  
  if (!is_string(sddl)) {
    stop("`sddl` must be a single string or an object built by `sd_create()`.")
  }

  name <- maybe_prefix(name)

  con <- cpp_np_connection(
    name,
    sddl,
    isTRUE(server),
    isTRUE(blocking),
    as.double(round(max_instances, 0)),
    as.double(timeout)
  )

  if (nzchar(open)) {
    tryCatch(
      base::open(con, open, blocking = isTRUE(blocking)),
      error = function(e) {
        close(con)
        stop(e)
      }
    )
  }

  con
}


#' @rdname winpipe
#' @export
open.winpipe <- function(con, open = "r+", blocking = FALSE, ...) {
  open.connection(con, open = open, blocking = blocking, ...)
}


#' @rdname winpipe
#' @export
is_winpipe <- function(x) {
  inherits(x, "winpipe")
}


check_winpipe <- function(x) {
  if (!is_winpipe(x)) {
    stop(sprintf("Expected an object of class `winpipe`, got `%s`.", class(x)))
  }
}


#' @rdname winpipe
#' @export
np_listen <- function(con) {
  invisible(cpp_np_conn_accept(con))
}


#' @rdname winpipe
#' @export
np_disconnect <- function(con) {
  invisible(cpp_np_conn_disconnect(con))
}


#' @rdname winpipe
#' @export
np_exists <- function(name) {
  name <- maybe_prefix(name)
  cpp_np_conn_exists(name)
}


#' @rdname winpipe
#' @export
np_list <- function() {
  cpp_np_list()
}


maybe_prefix <- function(name) {
  prefix <- r"(\\.\pipe\)"
  if (!startsWith(name, prefix)) {
    name <- paste0(prefix, name)
  }
  name
}