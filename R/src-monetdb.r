#' Connect to MonetDB (http://www.monetdb.org), an Open Source analytics-focused database
#'
#' Use \code{src_monetdb} to connect to an existing MonetDB database,
#' and \code{tbl} to connect to tables within that database.
#' If you are running a local database with, you only need to define the name of the database you want to connect to.
#'
#' @template db-info
#' @param dbname Database name
#' @param host,port Host name and port number of database (defaults to localhost:50000)
#' @param user,password User name and password (if needed)
#' @param ... for the src, other arguments passed on to the underlying
#'   database connector, \code{dbConnect}.
#' @param src a MonetDB src created with \code{src_monetdb}.
#' @param from Either a string giving the name of table in database, or
#'   \code{\link{sql}} described a derived table or compound join.
#' @export
#' @examples
#' \dontrun{
#' # Connection basics ---------------------------------------------------------
#' # To connect to a database first create a src:
#' my_db <- src_monetdb(dbname="demo",host = "localhost", port=50000, user = "monetdb",
#'   password = "monetdb")
#' # Then reference a tbl within that src
#' my_tbl <- tbl(my_db, "my_table")
#' }
#'
#' # Here we'll use the Lahman database: to create your own local copy,
#' # create a local database called "lahman" first.
#'
#' if (has_lahman("monetdb")) {
#' # Methods -------------------------------------------------------------------
#' batting <- tbl(lahman_monetdb(), "Batting")
#' dim(batting)
#' colnames(batting)
#' head(batting)
#'
#' # Data manipulation verbs ---------------------------------------------------
#' filter(batting, yearID > 2005, G > 130)
#' select(batting, playerID:lgID)
#' arrange(batting, playerID, desc(yearID))
#' summarise(batting, G = mean(G), n = n())
#' mutate(batting, rbi2 = if(is.null(AB)) 1.0 * R / AB else 0)
#'
#' # note that all operations are lazy: they don't do anything until you
#' # request the data, either by `print()`ing it (which shows the first ten
#' # rows), by looking at the `head()`, or `collect()` the results locally.
#'
#' system.time(recent <- filter(batting, yearID > 2010))
#' system.time(collect(recent))
#'
#' # Group by operations -------------------------------------------------------
#' # To perform operations by group, create a grouped object with group_by
#' players <- group_by(batting, playerID)
#' group_size(players)
#' summarise(players, mean_g = mean(G), best_ab = max(AB))
#'
#' # When you group by multiple level, each summarise peels off one level
#' per_year <- group_by(batting, playerID, yearID)
#' stints <- summarise(per_year, stints = max(stint))
#' filter(stints, stints > 3)
#' summarise(stints, max(stints))
#'
#' # Joins ---------------------------------------------------------------------
#' player_info <- select(tbl(lahman_monetdb(), "Master"), playerID, hofID,
#'   birthYear)
#' hof <- select(filter(tbl(lahman_monetdb(), "HallOfFame"), inducted == "Y"),
#'  hofID, votedBy, category)
#'
#' # Match players and their hall of fame data
#' inner_join(player_info, hof)
#' # Keep all players, match hof data where available
#' left_join(player_info, hof)
#' # Find only players in hof
#' semi_join(player_info, hof)
#' # Find players not in hof
#' anti_join(player_info, hof)
#'
#' # Arbitrary SQL -------------------------------------------------------------
#' # You can also provide sql as is, using the sql function:
#' batting2008 <- tbl(lahman_monetdb(),
#'   sql('SELECT * FROM "Batting" WHERE "yearID" = 2008'))
#' batting2008
#' }
src_monetdb <- function(dbname, host = "localhost", port = 50000L, user = "monetdb", 
  password = "monetdb", ...) {
  if (!require("MonetDB.R")) {
    stop("MonetDB.R package required to connect to MonetDB", call. = FALSE)
  }
  
  con <- dbi_connect(MonetDB.R(), dbname = dbname , host = host, port = port, 
    username = user, password = password, ...)
  info <- db_info(con)
  
  src_sql("monetdb", con, 
    info = info, disco = db_disconnector(con, "monetdb"))
}

tbl.src_monetdb <- function(src, from, ...) {
  if (grepl("ORDER BY|LIMIT|OFFSET",as.character(from),ignore.case=T)) {
    stop(paste0(from," contains ORDER BY, LIMIT or OFFSET keywords, which are not supported. Sorry."))
  }
  tbl_sql("monetdb", src = src, from = from, ...)
}

brief_desc.src_monetdb <- function(x) {
  paste0("MonetDB ",x$info$monet_version, " (",x$info$monet_release, ") [", x$info$merovingian_uri,"]")
}

#' @export
translate_env.src_monetdb <- function(x) {
  sql_variant(
    base_scalar,
    sql_translator(.parent = base_agg,
      n = function() sql("count(*)"),
      # check & extend!
      sd =  sql_prefix("stddev_samp"),
      var = sql_prefix("var_samp"),
      paste = function(x, collapse) build_sql("group_concat(", x, collapse, ")")
    )
  )
}

#' @export
sql_begin_trans.MonetDBConnection <- function(con) {
  qry_run(con, "start transaction")
}

# lifted from postgres equivalent
sql_insert_into.MonetDBConnection <- function(con, table, values) {
  # Convert factors to strings
  is_factor <- vapply(values, is.factor, logical(1))
  values[is_factor] <- lapply(values[is_factor], as.character)

  # Encode special characters in strings
  is_char <- vapply(values, is.character, logical(1))
  values[is_char] <- lapply(values[is_char], encodeString)

  tmp <- tempfile(fileext = ".csv")
  write.table(values, tmp, sep = ",", quote = T,
    row.names = FALSE, col.names = FALSE,na="")

  sql <- build_sql("COPY ",sql(nrow(values))," RECORDS INTO ", ident(table)," FROM ",tmp," USING DELIMITERS ',','\\n','\"' NULL AS ''",
    con = con)
  qry_run(con, sql)

  invisible()
}

# Chuck Norris (and MonetDB) do not need ANALYZE
sql_analyze.MonetDBConnection <- function(con, table) {
  invisible(TRUE) 
}

# MonetDB does not benefit from indices
sql_create_indexes.MonetDBConnection <- function(con, table, indexes = NULL, ...) {
  invisible(TRUE) 
}

# prepare gives us column info without actually running a query
qry_fields.MonetDBConnection <- function(con, from) {
  dbGetQuery(con,paste0("PREPARE SELECT * FROM ", from))$column
}
