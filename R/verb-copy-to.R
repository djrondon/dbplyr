#' Copy a local data frame to a remote database
#'
#' @description
#' This is an implementation of the dplyr [copy_to()] generic and it mostly
#' a wrapper around [DBI::dbWriteTable()].
#'
#' It is useful for copying small amounts of data to a database for examples,
#' experiments, and joins. By default, it creates temporary tables which are
#' only visible within the current connection to the database.
#'
#' @export
#' @param df A local data frame, a `tbl_sql` from same source, or a `tbl_sql`
#'   from another source. If from another source, all data must transition
#'   through R in one pass, so it is only suitable for transferring small
#'   amounts of data.
#' @param types a character vector giving variable types to use for the columns.
#'    See \url{http://www.sqlite.org/datatype3.html} for available types.
#' @param temporary if `TRUE`, will create a temporary table that is
#'   local to this connection and will be automatically deleted when the
#'   connection expires
#' @param unique_indexes a list of character vectors. Each element of the list
#'   will create a new unique index over the specified column(s). Duplicate rows
#'   will result in failure.
#' @param indexes a list of character vectors. Each element of the list
#'   will create a new index.
#' @param analyze if `TRUE` (the default), will automatically ANALYZE the
#'   new table so that the query optimiser has useful information.
#' @param in_transaction Should the table creation be wrapped in a transaction?
#'   This typically makes things faster, but you may want to suppress if the
#'   database doesn't support transactions, or you're wrapping in a transaction
#'   higher up (and your database doesn't support nested transactions.)
#' @inheritParams dplyr::copy_to
#' @inherit arrange.tbl_lazy return
#' @examples
#' library(dplyr, warn.conflicts = FALSE)
#'
#' df <- data.frame(x = 1:5, y = letters[5:1])
#' db <- copy_to(src_memdb(), df)
#' db
#'
#' df2 <- data.frame(y = c("a", "d"), fruit = c("apple", "date"))
#' # copy_to() is called automatically if you set copy = TRUE
#' # in the join functions
#' db %>% left_join(df2, copy = TRUE)
#' @importFrom dplyr copy_to
copy_to.src_sql <- function(dest, df, name = deparse(substitute(df)),
                            overwrite = FALSE, types = NULL, temporary = TRUE,
                            unique_indexes = NULL, indexes = NULL,
                            analyze = TRUE, ...,
                            in_transaction = TRUE
                            ) {
  assert_that(is.flag(temporary))

  if (!is.data.frame(df) && !inherits(df, "tbl_sql")) {
    stop("`df` must be a local dataframe or a remote tbl_sql", call. = FALSE)
  }

  name <- as.sql(name, con = dest$con)

  if (inherits(df, "tbl_sql") && same_src(df$src, dest)) {
    out <- compute(df,
      name = name,
      temporary = temporary,
      unique_indexes = unique_indexes,
      indexes = indexes,
      analyze = analyze,
      ...
    )
  } else {
    # avoid S4 dispatch problem in dbSendPreparedQuery
    df <- as.data.frame(collect(df))

    name <- db_copy_to(dest$con, name, df,
      overwrite = overwrite,
      types = types,
      temporary = temporary,
      unique_indexes = unique_indexes,
      indexes = indexes,
      analyze = analyze,
      in_transaction = in_transaction,
      ...
    )

    out <- tbl(dest, name)
  }

  invisible(out)
}

#' @importFrom dplyr auto_copy
#' @export
auto_copy.tbl_sql <- function(x, y, copy = FALSE, ...) {
  copy_to(x$src, as.data.frame(y), unique_table_name(), ...)
}

#' More db generics
#'
#' These are new, so not included in dplyr for backward compatibility
#' purposes.
#'
#' @keywords internal
#' @export
db_copy_to <-  function(con, table, values,
                        overwrite = FALSE, types = NULL, temporary = TRUE,
                        unique_indexes = NULL, indexes = NULL,
                        analyze = TRUE, ...,
                        in_transaction = TRUE) {
  UseMethod("db_copy_to")
}

#' @export
db_copy_to.DBIConnection <- function(con, table, values,
                            overwrite = FALSE, types = NULL, temporary = TRUE,
                            unique_indexes = NULL, indexes = NULL,
                            analyze = TRUE, ...,
                            in_transaction = TRUE) {

  with_transaction(con, in_transaction, {
    table <- db_write_table(con, table,
      types = types,
      values = values,
      temporary = temporary,
      overwrite = overwrite
    )
    create_indexes(con, table, unique_indexes, unique = TRUE)
    create_indexes(con, table, indexes, unique = FALSE)
    if (analyze) db_analyze(con, table)
  })

  table
}

create_indexes <- function(con, table, indexes = NULL, unique = FALSE, ...) {
  if (is.null(indexes)) return()
  assert_that(is.list(indexes))

  for (index in indexes) {
    db_create_index(con, table, index, unique = unique, ...)
  }
}

# Don't use `tryCatch()` because it messes with the callstack
with_transaction <- function(con, in_transaction, code) {
  if (in_transaction) {
    dbBegin(con)
    on.exit(dbRollback(con))
  }

  code

  if (in_transaction) {
    on.exit()
    dbCommit(con)
  }
}
