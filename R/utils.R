is_windows <- function() {
  .Platform$OS.type == "windows"
}


list_invert <- function(x) {
  as.list(setNames(names(x), unlist(x)))
}


is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}


is_number <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x)
}


irenv <- new.env(parent = emptyenv())
check_repeated_interrupt <- function() {
  if (as.double(Sys.time()) - irenv$last_interrupt < 1) {
    stop("Interrupting", call. = FALSE)
  }
  irenv$last_interrupt <- as.double(Sys.time())
}


tabular <- function(df, ...) {
  stopifnot(is.data.frame(df))

  align <- function(x) if (is.numeric(x)) "r" else "l"
  col_align <- vapply(df, align, character(1))

  cols <- lapply(df, format, ...)
  contents <- do.call("paste",
    c(cols, list(sep = " \\tab ", collapse = "\\cr\n  ")))

  paste("\\tabular{", paste(col_align, collapse = ""), "}{\n  ",
    paste0("\\strong{", names(df), "}", sep = "", collapse = " \\tab "), " \\cr\n  ",
    contents, "\n}\n", sep = "")
}