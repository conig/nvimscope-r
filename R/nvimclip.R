#' nvimclip
#'
#' @param objname Name of the object to be processed. Default is "mtcars".
#' @return JSON representation of the processed object, copied to the clipboard.
#' @importFrom future.apply future_lapply
#' @export
nvimclip <- function(obj) {
  if (!dir.exists("/tmp/nvim-rmdclip")) {
    dir.create("/tmp/nvim-rmdclip", recursive = TRUE)
  }
  contents <- tryCatch(
    {
      as.list(obj)
    },
    error = function(e) {
      writeLines("", "/tmp/nvim-rmdclip/error.json")
      stop("Could not find object.")
    }
  )

  if(is.null(obj)){
    writeLines("", "/tmp/nvim-rmdclip/error.json")
    stop("Could not find object.")
  }

  if (is(obj, "data.frame")) {
    if (nrow(obj) * ncol(obj) > 1000000) {
      use_cores <- max(c(future::availableCores() - 10, 1))
      original_plan <- future::plan()
      future::plan("multicore", workers = use_cores)
      use_cores <- TRUE
    } else {
      future::plan("sequential")
      use_cores <- FALSE
    }
  }
  contents_names <- names(contents)
  out <- future.apply::future_lapply(seq_along(contents), function(i) {
    name <- contents_names[i]
    if (is.null(name)) name <- i
    x <- contents[[i]]
    data.frame(name = name, contents = process_contents(x, name))
  }) |>
    data.table::rbindlist(ignore.attr = TRUE) |>
    jsonlite::toJSON(pretty = TRUE, escape_unicode = FALSE) |>
    writeLines("/tmp/nvim-rmdclip/menu.json")
  if (use_cores) {
    future::plan(original_plan)
  }
}

#' process_contents
#'
#' @param x Object to be processed.
#' @param name Name of the object.
#' @return Processed content as a string.
#' @export

process_contents <- function(x, name) {
  if (is(x, "numeric")) {
    return(process_numeric(x, name))
  }
  if (is(x, "character")) {
    return(process_character(x, name))
  }

  if (is(x, "factor")) {
    return(process_character(x, name))
  }

  if (is(x, "logical")) {
    return(process_character(x, name))
  }

  process_else(x, name)
}

#' process_numeric
#'
#' @param x Numeric object to be processed.
#' @param name Name of the object.
#' @return Processed numeric content as a string.

process_numeric <- function(x, name) {
  if (length(x) < 2) {
    return(capture.output(print(x)) |> paste(collapse = "\n"))
  }
  if (is.null(name)) name <- ""
  mean_x <- mean(x, na.rm = TRUE) |> round(2)
  median_x <- median(x, na.rm = TRUE) |> round(2)
  sd_x <- sd(x, na.rm = TRUE) |> round(2)
  IQR_x <- IQR(x, na.rm = TRUE) |> round(2)

  range_x <- range(x, na.rm = TRUE) |>
    round(2) |>
    paste(collapse = ", ")
  density_x <- tryCatch(
    {
      if (length(x) > 1000000) {
        x_dens <- sample(x, 1000000)
        msg <- "*Plot based on a random sample\n  of 1,000,000 observations."
      } else {
        x_dens <- x
        msg <- ""
      }

      capture.output(txtplot::txtdensity(na.omit(x_dens), width = 45, height = 19)) |>
        paste(collapse = "\n")
    },
    error = function(e) {
      return("Could not generate density plot.")
    }
  )

  head_x <- head(x, 5) |>
    capture.output() |>
    paste(collapse = "\n")
  tail_x <- tail(x, 5) |>
    capture.output() |>
    paste(collapse = "\n")
  kurtosis_x <- psych::kurtosi(x) |> round(2)
  skewness_x <- psych::skew(x) |> round(2)

  is_missing_x <- sum(is.na(x))
  missing_pc <- (is_missing_x / length(x)) * 100
  missing_pc <- missing_pc |> round(2)

  class_x <- class(x) |> paste(collapse = ", ")

  len_x <- length(x)

  glue::glue("



  Name: `{name}` <{class_x}>

—————————————————————————————————————————————

  head: {head_x}
  tail: {tail_x}

  Observations: {len_x}
  Unique values: {length(unique(x))}
  Missing: {is_missing_x} ({missing_pc}%)

  Range: [{range_x}]
  Mean: {mean_x} (sd: {sd_x})
  Median: {median_x} (IQR: {IQR_x})

  Kurtosis: {kurtosis_x}
  Skewness: {skewness_x}

—————————————————————————————————————————————

  {density_x}
  {msg}

             ")
}

#' process_character
#'
#' @param x Character object to be processed.
#' @param name Name of the object.
#' @return Processed character content as a string.

process_character <- function(x, name) {
  if (length(x) < 2) {
    return(capture.output(print(x)) |> paste(collapse = "\n"))
  }
  if (is.null(name)) name <- ""

  head_x <- head(x, 5) |>
    capture.output() |>
    paste(collapse = "\n")
  tail_x <- tail(x, 5) |>
    capture.output() |>
    paste(collapse = "\n")

  is_missing_x <- sum(is.na(x))
  missing_pc <- (is_missing_x / length(x)) * 100
  missing_pc <- missing_pc |> round(2)

  len_x <- length(x)

  values <- table(x)
  most_common <- data.frame(values)
  most_common <- most_common[order(-most_common$Freq), ]
  if (nrow(most_common) > 5) {
    most_common <- most_common[1:5, ]
  }

  most_common_string <- glue::glue("`{most_common[,1]}`: {most_common[,2]}") |>
    paste(collapse = "\n  ")

  class_x <- class(x) |> paste(collapse = ", ")

  glue::glue("
  


  Name: `{name}` <{class_x}>

—————————————————————————————————————————————

  head: {head_x}
  tail: {tail_x}

  Observations: {len_x}
  Unique values: {length(unique(x))}
  Missing: {is_missing_x} ({missing_pc}%)

  Most common values:
  {most_common_string}
             ")
}

#' process_else
#'
#' @param x Object to be processed.
#' @param name Name of the object.
#' @return Processed content as a string for objects that are not numeric, character, factor, or logical.

process_else <- function(x, name) {
  len_x <- length(x)

  if (length(x) > 40) {
    x <- x[1:40]
    msg <- "..."
  } else {
    msg <- ""
  }
  print_contents <- capture.output(print(x))

  print_contents <- paste(print_contents, collapse = "\n  ")
  class_x <- class(x) |> paste(collapse = ", ")
  glue::glue("
  


  Name: `{name}` <{class_x}>

—————————————————————————————————————————————

  Length: {len_x}

  {print_contents}
  {msg}
")
}
