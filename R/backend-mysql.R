#' Backend: MySQL/MariaDB
#'
#' @description
#' See `vignette("translate-function")` and `vignette("translate-verb")` for
#' details of overall translation technology. Key differences for this backend
#' are:
#'
#' * `paste()` uses `CONCAT_WS()`
#' * String translations for `str_detect()`, `str_locate()`, and
#'   `str_replace_all()`
#' * Clear error message for unsupported full joins
#'
#' Use `simulate_mysql()` with `lazy_frame()` to see simulated SQL without
#' converting to live access database.
#'
#' @name backend-mysql
#' @aliases NULL
#' @examples
#' library(dplyr, warn.conflicts = FALSE)
#'
#' lf <- lazy_frame(a = TRUE, b = 1, c = 2, d = "z", con = simulate_mysql())
#' lf %>% transmute(x = paste0(z, " times"))
NULL

#' @export
#' @rdname backend-mysql
simulate_mysql <- function() simulate_dbi("MariaDBConnection")

#' @export
db_desc.MariaDBConnection <- function(x) {
  info <- dbGetInfo(x)

  paste0(
    "mysql ", info$serverVersion, " [",
    info$user, "@", info$host, ":", info$port, "/", info$dbname,
    "]"
  )
}
#' @export
db_desc.MySQL <- db_desc.MariaDBConnection
#' @export
db_desc.MySQLConnection <- db_desc.MariaDBConnection

#' @export
sql_translate_env.MariaDBConnection <- function(con) {
  sql_variant(
    sql_translator(.parent = base_scalar,
      as.logical = function(x) {
        sql_expr(IF(x, TRUE, FALSE))
      },
      as.character = sql_cast("CHAR"),

      # string functions ------------------------------------------------
      paste = sql_paste(" "),
      paste0 = sql_paste(""),

      # stringr
      str_c = sql_paste(""),
      # https://dev.mysql.com/doc/refman/8.0/en/regexp.html
      # NB: case insensitive by default; could use REGEXP_LIKE for MySQL,
      # but available in MariaDB. A few more details at:
      # https://www.oreilly.com/library/view/mysql-cookbook/0596001452/ch04s11.html
      str_detect = sql_infix("REGEXP"),
      str_locate = function(string, pattern) {
        sql_expr(REGEXP_INSTR(!!string, !!pattern))
      },
      str_replace_all = function(string, pattern, replacement){
        sql_expr(regexp_replace(!!string, !!pattern, !!replacement))
      }
    ),
    sql_translator(.parent = base_agg,
      sd =  sql_aggregate("STDDEV_SAMP", "sd"),
      var = sql_aggregate("VAR_SAMP", "var"),
      str_flatten = function(x, collapse) {
        sql_expr(group_concat(!!x %separator% !!collapse))
      }
    ),
    sql_translator(.parent = base_win,
      sd = win_aggregate("STDDEV_SAMP"),
      var = win_aggregate("VAR_SAMP"),
      # GROUP_CONCAT not currently available as window function
      # https://mariadb.com/kb/en/library/aggregate-functions-as-window-functions/
      str_flatten = win_absent("str_flatten")
    )
  )
}

#' @export
sql_translate_env.MySQL <- sql_translate_env.MariaDBConnection
#' @export
sql_translate_env.MySQLConnection <- sql_translate_env.MariaDBConnection

#' @export
sql_table_analyze.MariaDBConnection <- function(con, table, ...) {
  build_sql("ANALYZE TABLE ", as.sql(table), con = con)
}
#' @export
sql_table_analyze.MySQL <- sql_table_analyze.MariaDBConnection
#' @export
sql_table_analyze.MySQLConnection <- sql_table_analyze.MariaDBConnection

#' @export
sql_join.MariaDBConnection <- function(con, x, y, vars, type = "inner", by = NULL, ...) {
  if (identical(type, "full")) {
    stop("MySQL does not support full joins", call. = FALSE)
  }
  NextMethod()
}
#' @export
sql_join.MySQL <- sql_join.MariaDBConnection
#' @export
sql_join.MySQLConnection <- sql_join.MariaDBConnection


#' @export
sql_expr_matches.MariaDBConnection <- function(con, x, y) {
  # https://dev.mysql.com/doc/refman/5.7/en/comparison-operators.html#operator_equal-to
  build_sql(x, " <=> ", y, con = con)
}
#' @export
sql_expr_matches.MySQL <- sql_expr_matches.MariaDBConnection
#' @export
sql_expr_matches.MySQLConnection <- sql_expr_matches.MariaDBConnection

globalVariables(c("%separator%", "group_concat", "IF", "REGEXP_INSTR"))

