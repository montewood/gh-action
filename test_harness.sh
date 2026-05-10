#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 로컬 테스트 하네스 — GitHub Actions 없이 ga_script.R 을 직접 실행합니다.
#
# 사전 조건:
#   gcloud 로그인 상태 (gcloud auth login)
#   Service Account Token Creator 권한 보유
#   (서비스 계정 임퍼소네이션으로 analytics 스코프 제한 우회)
#   필요 패키지: httr, jsonlite, dplyr (Rscript 에서 install.packages 로 설치 가능)
#
# 사용법:
#   bash test_harness.sh              # 어제 날짜로 실행
#   bash test_harness.sh 2026-05-01   # 특정 날짜로 실행
# ---------------------------------------------------------------------------
set -euo pipefail

TARGET_DATE="${1:-}"
PROJECT_ID="concrete-sol-450302-q3"
SA_EMAIL="ga-github-actions@${PROJECT_ID}.iam.gserviceaccount.com"

# ---- 1. access token (서비스 계정 임퍼소네이션) --------------------------
echo "[1/3] 서비스 계정 임퍼소네이션으로 access token 발급 중..."
ACCESS_TOKEN=$(gcloud auth print-access-token \
  --impersonate-service-account="${SA_EMAIL}" \
  --scopes="https://www.googleapis.com/auth/analytics.readonly" 2>/dev/null || true)

if [[ -z "$ACCESS_TOKEN" ]]; then
  cat <<'EOF'
ERROR: access token 을 가져오지 못했습니다.

가능한 원인:
  1) gcloud 로그인 미완료
  2) 현재 사용자에 Service Account Token Creator 권한 없음

확인/수정 예시:
  gcloud auth login
  gcloud iam service-accounts add-iam-policy-binding \
    ga-github-actions@concrete-sol-450302-q3.iam.gserviceaccount.com \
    --member="user:YOUR_EMAIL" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --project=concrete-sol-450302-q3
EOF
  exit 1
fi
echo "      토큰 발급 완료 (앞 20자: ${ACCESS_TOKEN:0:20}...)"

# ---- 2. 날짜 오버라이드 (선택) -------------------------------------------
EXTRA_ENV=""
if [[ -n "$TARGET_DATE" ]]; then
  echo "[2/3] 테스트 날짜를 ${TARGET_DATE} 로 설정합니다."
  EXTRA_ENV="TEST_DATE=${TARGET_DATE}"
else
  echo "[2/3] 날짜를 별도 지정하지 않음 → 스크립트 기본값(어제) 사용"
fi

# ---- 3. R 스크립트 실행 ---------------------------------------------------
echo "[3/3] Rscript assets/ga_script.R 실행 중..."
env GCP_ACCESS_TOKEN="$ACCESS_TOKEN" $EXTRA_ENV \
  Rscript assets/ga_script.R

echo ""
echo "완료! output/ 디렉터리에서 결과를 확인하세요."
