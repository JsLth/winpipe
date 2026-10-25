is_windows <- function() {
  .Platform$OS.type == "windows"
}


is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}


is_number <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x)
}


check_installed <- function(x, reason = NULL) {
  if (!is_installed(x)) {
    if (!is.null(reason)) {
      stop(sprintf(
        "Package `%s` required to %s. Install it with `install.packages(\"%s\")`.",
        x, reason, x
      ))
    } else {
      stop(sprintf("Package `%s` required. Install it with `install.packages(\"%s\")`.", x, x))
    }
  }
}


is_installed <- function(x) {
  suppressMessages(suppressWarnings(requireNamespace(x, quietly = TRUE)))
}


tabular <- function(df, ...) { # nocov start
  stopifnot(is.data.frame(df))

  align <- function(x) if (is.numeric(x)) "r" else "l"
  col_align <- vapply(df, align, character(1))

  cols <- lapply(df, format, ...)
  contents <- do.call("paste",
    c(cols, list(sep = " \\tab ", collapse = "\\cr\n  ")))

  paste("\\tabular{", paste(col_align, collapse = ""), "}{\n  ",
    paste0("\\strong{", names(df), "}", sep = "", collapse = " \\tab "), " \\cr\n  ",
    contents, "\n}\n", sep = "")
} # nocov end