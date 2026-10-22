# ⚠️ 폐기 예정 (v1 전용) — `terraform/edge`

이 디렉터리는 **v1 아키텍처**(API Gateway HTTP API + VPC Link V2 + 커스텀 도메인)의 스택입니다.

**v2에서는 사용하지 않습니다.** v2는 `internet-facing ALB + AWS WAF`가 진입점이고, Route 53 레코드는 [`../dns`](../dns) 스택이 담당합니다.

## 남겨둔 이유

이 디렉터리의 `terraform.tfstate`에 **아직 삭제되지 않은 v1 리소스**가 들어 있습니다.

- `aws_apigatewayv2_api` / `aws_apigatewayv2_vpc_link` / `aws_apigatewayv2_integration` / `aws_apigatewayv2_route` / `aws_apigatewayv2_stage`
- `aws_apigatewayv2_domain_name` / `aws_apigatewayv2_api_mapping`
- `aws_route53_record.app` (API Gateway 커스텀 도메인을 가리키던 A alias)

state 없이 디렉터리를 지우면 이 리소스들이 **과금된 채로 남습니다.**

## v2 전환 시 순서

```bash
# 1) v1 edge 리소스 제거 (API Gateway · VPC Link · 커스텀 도메인 A 레코드)
cd terraform/edge
terraform destroy

# 2) Ingress 삭제 → LBC 가 internal ALB 를 제거한다
#    (ALB 가 살아 있으면 ALB 보안그룹 교체가 "resource in use" 로 실패한다)
kubectl delete -f k8s/30-ingress.yaml
kubectl -n petclinic-dev get ingress                        # 목록이 비었는지 확인
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'   # ALB 삭제 확인

# 3) foundation 적용 — ingress 서브넷 제거, Cognito 제거, WAF 추가, ALB SG 교체
cd terraform
terraform apply

# 4) 새 Ingress 적용 → LBC 가 internet-facing ALB + WAF 연결을 생성한다
kubectl apply -f k8s/30-ingress.yaml
kubectl -n petclinic-dev get ingress petclinic-web -w       # ADDRESS 가 나올 때까지

# 5) 새 ALB 로 DNS 연결
cd dns
terraform init && terraform apply
```

> **주의 1**: 1)에서 VPC Link가 사라져야 3)에서 ingress 서브넷을 삭제할 수 있습니다.
> **주의 2**: ALB 보안그룹은 description 변경으로 **교체(replace)** 됩니다. ALB가 살아 있으면
> 삭제가 막히므로 반드시 2)에서 Ingress를 먼저 지웁니다.
> **주의 3**: 2)~4) 사이에 **서비스가 내려갑니다**(ALB 재생성, 수 분).
