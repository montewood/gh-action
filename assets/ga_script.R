library(httr)
library(jsonlite)
library(dplyr)

# --- 인증 ---
# YAML auth step(token_format: access_token)이 GCP_ACCESS_TOKEN env var로 전달
# googleAuthR/googleAnalyticsR을 사용하지 않고 GA4 Data API를 직접 호출
access_token <- Sys.getenv("GCP_ACCESS_TOKEN")
if (nchar(access_token) == 0) stop("GCP_ACCESS_TOKEN env var not set")

# --- 설정 ---
property_id <- 267577482
test_date_env <- Sys.getenv("TEST_DATE")
target_date <- if (nchar(test_date_env) > 0) as.Date(test_date_env) else Sys.Date() - 1
date_str    <- format(target_date, "%Y%m%d")
output_path <- file.path("output", paste0("GA-", date_str, ".json"))

message("Collecting GA4 data for: ", target_date)

# --- GA4 Data API v1beta runReport ---
body <- list(
  dateRanges = list(list(startDate = as.character(target_date),
                         endDate   = as.character(target_date))),
  metrics    = list(list(name = "activeUsers")),
  dimensions = list(list(name = "dateHourMinute")),
  limit      = 100000
)

resp <- POST(
  paste0("https://analyticsdata.googleapis.com/v1beta/properties/",
         property_id, ":runReport"),
  add_headers(Authorization = paste("Bearer", access_token)),
  content_type_json(),
  body = toJSON(body, auto_unbox = TRUE)
)

if (http_error(resp)) {
  stop("GA4 API error: ", content(resp, "text", encoding = "UTF-8"))
}

data <- content(resp, "parsed", encoding = "UTF-8")

if (is.null(data$rows) || length(data$rows) == 0) {
  message("No data returned for ", target_date, ". Skipping file write.")
  quit(status = 0)
}

# --- 응답 파싱 ---
rows <- data$rows
wday_labels <- c("Sunday", "Monday", "Tuesday", "Wednesday",
                 "Thursday", "Friday", "Saturday")

result <- bind_rows(lapply(rows, function(r) {
  dhm         <- r$dimensionValues[[1]]$value   # YYYYMMDDHHmm
  active_users <- as.integer(r$metricValues[[1]]$value)
  dt           <- as.Date(substr(dhm, 1, 8), "%Y%m%d")

  list(
    dateHourMinute            = dhm,
    activeUsers               = active_users,
    parsed_year               = substr(dhm, 1, 4),
    parsed_month              = substr(dhm, 5, 6),
    parsed_day                = substr(dhm, 7, 8),
    parsed_hour               = substr(dhm, 9, 10),
    parsed_minute             = substr(dhm, 11, 12),
    parsed_year_month         = paste0(substr(dhm,1,4), "-", substr(dhm,5,6), "-01"),
    parsed_year_month_day     = format(dt, "%Y-%m-%d"),
    parsed_year_month_day_hour = paste0(format(dt, "%Y-%m-%d"), " ",
                                        substr(dhm,9,10), ":", substr(dhm,11,12), ":00"),
    parsed_week               = as.integer(format(dt, "%V")),
    parsed_wday               = as.integer(format(dt, "%u")) %% 7L + 1L,
    parsed_wday_label         = wday_labels[as.integer(format(dt, "%u")) %% 7L + 1L]
  )
}))

# --- 저장 ---
dir.create("output", showWarnings = FALSE)
# Legacy compatibility: historical files store one pretty-printed JSON payload
# as a single string element in a JSON array.
legacy_payload <- toJSON(result, auto_unbox = TRUE, pretty = TRUE)
write_json(list(legacy_payload), output_path, auto_unbox = FALSE, pretty = FALSE)
message("Saved ", nrow(result), " rows to ", output_path)
