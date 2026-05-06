library(googleAnalyticsR)
library(jsonlite)
library(dplyr)

# --- 인증 ---
# google-github-actions/auth@v2 가 GOOGLE_APPLICATION_CREDENTIALS 환경변수에
# WIF 임시 토큰 파일 경로를 자동으로 설정함 (JSON 키 불필요)
ga_auth(json_file = Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS"))

# --- 설정 ---
property_id <- 267577482          # assets/email_account 2번째 줄
target_date <- Sys.Date() - 1    # 어제 날짜 기준 수집

date_str    <- format(target_date, "%Y%m%d")
output_path <- file.path("output", paste0("GA-", date_str, ".json"))

message("Collecting GA4 data for: ", target_date)

# --- GA4 데이터 조회 ---
raw <- ga_data(
  property_id,
  date_range = c(as.character(target_date), as.character(target_date)),
  metrics    = "activeUsers",
  dimensions = "dateHourMinute",
  limit      = -1
)

if (nrow(raw) == 0) {
  message("No data returned for ", target_date, ". Writing empty array.")
  write(toJSON(list(), auto_unbox = FALSE), output_path)
  quit(status = 0)
}

# --- dateHourMinute 파싱 (기존 output 스키마 유지) ---
# dateHourMinute 형식: YYYYMMDDHHmm (12자리)
wday_labels <- c("Sunday", "Monday", "Tuesday", "Wednesday",
                 "Thursday", "Friday", "Saturday")

result <- raw %>%
  mutate(
    parsed_year               = substr(dateHourMinute, 1, 4),
    parsed_month              = substr(dateHourMinute, 5, 6),
    parsed_day                = substr(dateHourMinute, 7, 8),
    parsed_hour               = substr(dateHourMinute, 9, 10),
    parsed_minute             = substr(dateHourMinute, 11, 12),
    parsed_year_month         = paste0(parsed_year, "-", parsed_month, "-01"),
    parsed_year_month_day     = paste0(parsed_year, "-", parsed_month, "-", parsed_day),
    parsed_year_month_day_hour = paste0(
      parsed_year, "-", parsed_month, "-", parsed_day,
      " ", parsed_hour, ":", parsed_minute, ":00"
    ),
    .dt                       = as.Date(parsed_year_month_day),
    parsed_week               = as.integer(format(.dt, "%V")),
    # %u: 1=Mon..7=Sun → 변환해서 1=Sun..7=Sat (lubridate wday 기본값과 동일)
    parsed_wday               = as.integer(format(.dt, "%u")) %% 7L + 1L,
    parsed_wday_label         = wday_labels[parsed_wday]
  ) %>%
  select(-.dt)

# --- 저장 ---
dir.create("output", showWarnings = FALSE)
write_json(result, output_path, auto_unbox = TRUE, pretty = FALSE)

message("Saved ", nrow(result), " rows to ", output_path)
