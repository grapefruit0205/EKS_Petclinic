#!/usr/bin/env bash
###############################################################################
# 30-ingress.yaml 플레이스홀더 → 실제 AWS 값 치환
#
#   왜 필요한가:
#     공개 저장소에는 계정 ID 가 들어간 ACM/WAF ARN 을 넣을 수 없다.
#     그래서 repo 에는 <PLACEHOLDER> 버전만 두고,
#     배포 직전에 terraform output 을 읽어 실제값 파일을 만든다.
#
#   사용법:
#     ./k8s/render-ingress.sh          # k8s/30-ingress.rendered.yaml 생성
#     kubectl apply -f k8s/30-ingress.rendered.yaml
#
#   *.rendered.yaml 은 .gitignore 로 제외된다.
###############################################################################
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tfdir="${TF_DIR:-$here/../terraform}"
src="$here/30-ingress.yaml"
dst="$here/30-ingress.rendered.yaml"

for f in "$tfdir" "$src"; do
  [ -e "$f" ] || { echo "없음: $f" >&2; exit 1; }
done

tf() { terraform -chdir="$tfdir" output -raw "$1"; }

subnets_json="$(terraform -chdir="$tfdir" output -json public_subnet_ids)"
subnet_a="$(printf '%s' "$subnets_json" | python3 -c 'import json,sys;print(json.load(sys.stdin)[0])')"
subnet_b="$(printf '%s' "$subnets_json" | python3 -c 'import json,sys;print(json.load(sys.stdin)[1])')"
alb_sg="$(tf alb_sg_id)"
acm_arn="$(tf acm_certificate_arn)"
waf_arn="$(tf waf_web_acl_arn)"

echo "public subnets : $subnet_a , $subnet_b"
echo "alb sg         : $alb_sg"
echo "acm arn        : $acm_arn"
echo "waf arn        : $waf_arn"

sed \
  -e "/^[[:space:]]*#/!s|<PUBLIC_SUBNET_ID_A>|$subnet_a|g" \
  -e "/^[[:space:]]*#/!s|<PUBLIC_SUBNET_ID_B>|$subnet_b|g" \
  -e "/^[[:space:]]*#/!s|<ALB_SECURITY_GROUP_ID>|$alb_sg|g" \
  -e "/^[[:space:]]*#/!s|<ACM_CERTIFICATE_ARN>|$acm_arn|g" \
  -e "/^[[:space:]]*#/!s|<WAF_WEB_ACL_ARN>|$waf_arn|g" \
  "$src" > "$dst"

if grep -vE '^[[:space:]]*#' "$dst" | grep -qE '<(PUBLIC_SUBNET_ID_A|PUBLIC_SUBNET_ID_B|ALB_SECURITY_GROUP_ID|ACM_CERTIFICATE_ARN|WAF_WEB_ACL_ARN)>'; then
  echo "치환되지 않은 플레이스홀더가 남아 있습니다." >&2
  exit 1
fi

echo "생성: $dst"
