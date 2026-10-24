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


check_installed <- function(x) {
  if (!is_installed(x)) {
    stop(sprintf("Package `%s` required. Install it with `install.packages(\"%s\")`.", x, x))
  }
}


is_installed <- function(x) {
  suppressMessages(suppressWarnings(requireNamespace(x, quietly = TRUE)))
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