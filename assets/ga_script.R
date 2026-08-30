library(httr)
library(jsonlite)

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
# 날짜 차원으로 조회해 하루치 고유 사용자 수를 그대로 받는다. 분 단위(dateHourMinute)
# 응답을 합산하던 이전 방식은 같은 사용자가 여러 분에 걸쳐 활동하면 중복 계산됐다.
body <- list(
  dateRanges = list(list(startDate = as.character(target_date),
                         endDate   = as.character(target_date))),
  metrics    = list(list(name = "activeUsers"), list(name = "totalUsers")),
  dimensions = list(list(name = "date"))
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

# --- 응답 파싱 ---
metric_at <- function(row, index) {
  value <- suppressWarnings(as.integer(row$metricValues[[index]]$value))
  if (is.na(value)) 0L else value
}

if (is.null(data$rows) || length(data$rows) == 0) {
  active_users <- 0L
  total_users  <- 0L
} else {
  row <- data$rows[[1]]
  active_users <- metric_at(row, 1)
  total_users  <- metric_at(row, 2)
}

payload <- list(
  schemaVersion = 2L,
  date          = format(target_date, "%Y-%m-%d"),
  activeUsers   = active_users,
  totalUsers    = total_users
)

# --- 저장 ---
# 방문자가 0인 날도 파일을 남긴다. 파일 부재를 정상으로 취급하던 이전 동작이
# 2026-07-20부터 26일간의 수집 중단을 성공으로 보이게 만들었다.
#
# 다만 이미 있는 파일을 0으로 덮어쓰지는 않는다. GA4 기본 이벤트 보존기간이
# 2개월이라 오래된 날짜를 백필하면 실제 방문이 있었더라도 0이 돌아온다.
if (active_users == 0L && total_users == 0L && file.exists(output_path)) {
  message("Refusing to overwrite existing ", output_path, " with a zero result.")
} else {
  dir.create("output", showWarnings = FALSE)
  write_json(payload, output_path, auto_unbox = TRUE, pretty = TRUE)
  message("Saved activeUsers=", active_users, " totalUsers=", total_users,
          " to ", output_path)
}

# 워크플로가 0 방문 경고를 띄울 수 있도록 결과를 넘긴다.
github_output <- Sys.getenv("GITHUB_OUTPUT")
if (nchar(github_output) > 0) {
  write(c(paste0("active_users=", active_users),
          paste0("total_users=", total_users),
          paste0("date_str=", date_str)),
        file = github_output, append = TRUE)
}
