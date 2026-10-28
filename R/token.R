#' Security token information
#'
#' @description
#' Query the Windows access token associated with a named pipe client or with
#' the calling R process.
#' 
#' \code{np_whoami()} returns information about a token's user. \code{np_token_info()}
#' returns the full token details.
#'
#' @param con \code{[winpipe]} or \code{NULL}.
#'
#' The server end of a connected pipe, to query the connected client's token,
#' or \code{NULL} (default) to query the token of the R process itself.
#' @returns
#' \code{np_whoami()} returns a string of the form \code{"DOMAIN\\\\user"}.
#'
#' \code{np_token_info()} returns a list with:
#' 
#' \itemize{
#'  \item \code{user}: if possible, a user name as \code{"DOMAIN\\\\user"}.
#'  \item \code{sid}: user SID string.
#'  \item \code{groups}: a data frame of group names, SIDs, and whether each group
#'    is enabled.
#'  \item \code{elevated}: whether the token is elevated, i.e. runs with admin rights.
#'  \item \code{integrity}: integrity level, i.e., what objects can a client touch? Can be one of: \itemize{
#'   \item{\code{"low"}: low-permission users, e.g., protected apps or sandboxes}
#'   \item{\code{"medium"}: standard users}
#'   \item{\code{"high"}: admin users}
#'   \item{\code{"system"}: OS services}
#'  }
#'  \item \code{token_type}: \code{"primary"} (own process) or \code{"impersonation"}
#'    (pipe client).
#'  \item \code{impersonation_level}: level at which the server can impersonate. Can be one of: \itemize{
#'   \item{\code{"anonymous"}: server cannot obtain any information}
#'   \item{\code{"identification"}: server can identify the client's SID and groups}
#'   \item{\code{"impersonation"}: server can act as the client locally}
#'   \item{\code{"delegation"}: server can act as the client locally and remotely}
#'   \item{\code{NA}: for primary tokens}
#'  }
#' }
#' 
#' @export
#' 
#' @examples
#' # If no argument is provided, returns the SID
#' # of the R session
#' np_whoami()
#' 
#' # If a server-client structure is provided
#' # returns the SID of the client
#' server <- winpipe("test")
#' client <- winpipe("test")
#' np_whoami(server)
#' 
#' close(client)
#' close(server)
np_whoami <- function(con = NULL) {
  np_token_info(con)$user
}


#' @rdname np_whoami
#' @export
np_token_info <- function(con = NULL) {
  if (is.null(con)) {
    cpp_np_token_info(NULL, FALSE)
  } else {
    check_winpipe(con)
    cpp_np_token_info(con, TRUE)
  }
}
