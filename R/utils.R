deparse_trunc <- function(x, width = getOption("width")) {
  text <- deparse(x, width.cutoff = width)
  if (length(text) == 1 && nchar(text) < width) return(text)

  paste0(substr(text[1], 1, width - 3), "...")
}

is.wholenumber <- function(x) {
  trunc(x) == x
}

deparse_all <- function(x) {
  x <- purrr::map_if(x, is_formula, f_rhs)
  purrr::map_chr(x, expr_text, width = 500L)
}

#' Provides comma-separated string out of the parameters
#' @export
#' @keywords internal
#' @param ... Arguments to be constructed into the string
named_commas <- function(...) {
  x <- unlist(purrr::map(list2(...), as.character))
  if (is_null(names(x))) {
    paste0(x, collapse = ", ")
  } else {
    paste0(names(x), " = ", x, collapse = ", ")
  }
}

commas <- function(...) paste0(..., collapse = ", ")

in_travis <- function() identical(Sys.getenv("TRAVIS"), "true")

unique_table_name <- function() {
  # Needs to use option to unique names across reloads while testing
  i <- getOption("dbplyr_table_name", 0) + 1
  options(dbplyr_table_name = i)
  sprintf("dbplyr_%03i", i)
}
unique_subquery_name <- function() {
  # Needs to use option so can reset at the start of each query
  i <- getOption("dbplyr_subquery_name", 0) + 1
  options(dbplyr_subquery_name = i)
  sprintf("q%02i", i)
}
unique_subquery_name_reset <- function() {
  options(dbplyr_subquery_name = 0)
}

succeeds <- function(x, quiet = FALSE) {
  tryCatch(
    {
      x
      TRUE
    },
    error = function(e) {
      if (!quiet)
        message("Error: ", e$message)
      FALSE
    }
  )
}

c_character <- function(...) {
  x <- c(...)
  if (length(x) == 0) {
    return(character())
  }

  if (!is.character(x)) {
    stop("Character input expected", call. = FALSE)
  }

  x
}

cat_line <- function(...) cat(paste0(..., "\n"), sep = "")

res_warn_incomplete <- function(res, hint = "n = -1") {
  if (dbHasCompleted(res)) return()

  rows <- big_mark(dbGetRowCount(res))
  warning("Only first ", rows, " results retrieved. Use ", hint, " to retrieve all.",
    call. = FALSE)
}
