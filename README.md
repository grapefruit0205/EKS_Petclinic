# EKS_Petclinic — ALB · WAF 기반 3-Tier 구축

> Spring Petclinic(Spring MVC/JSP)을 **internet-facing ALB + AWS WAF → Nginx Web → Tomcat App → RDS MySQL** 구조로 AWS에 올리는 프로젝트입니다.
> Terraform 코드, Kubernetes 매니페스트, 컨테이너 빌드 정의, 설계·구축 문서를 함께 담았습니다.

> **v2 전환 완료 (2026-10-22)**: API Gateway HTTP API · VPC Link V2 · internal ALB · Cognito를 **제거**하고 **internet-facing ALB + AWS WAF** 직접 진입으로 전환했으며, **실제 AWS에 적용·검증까지 마쳤습니다.**
> VPC는 4계층 → **3계층**(public / private workloads / isolated data)으로 축소했습니다. 전환 이력은 [`docs/구축_결과.md`](docs/구축_결과.md) 0장에 있습니다.

> **토폴로지 다이어그램**: [`docs/아키텍처_토폴로지.drawio`](docs/아키텍처_토폴로지.drawio) — **v2 기준**(internet-facing ALB + AWS WAF, 3계층 VPC)입니다. [draw.io](https://app.diagrams.net) 또는 VS Code Draw.io 확장으로 엽니다.
> (`.drawio`는 XML이라 GitHub에서 이미지로 렌더링되지 않습니다.)

---

## 1. 목표 아키텍처 (v2)

```text
사용자 브라우저
   │ HTTPS 443  (clinic.<도메인>)
   ▼
Route 53 (A alias) ── ACM 인증서 (ap-northeast-2, Regional)
   ▼
internet-facing ALB  (public 서브넷 2개 AZ)
   │  ← AWS WAF Regional WebACL
   │  target-type: ip
   ▼
┌──────────────────────── VPC 10.20.0.0/16 ────────────────────────┐
│  Tier 1  Nginx Web      ×2  (8080 업무 / 8081 health)            │
│  Tier 2  Tomcat App     ×2  (Spring MVC · JSP · JDK21)           │
│  Tier 3  RDS MySQL 8.4.6    (Multi-AZ · isolated data 서브넷)     │
└──────────────────────────────────────────────────────────────────┘
```

- **외부 진입점은 ALB 하나**이고, 그 앞단에 **AWS WAF**가 붙습니다.
- VPC는 **3계층**(public / private workloads / isolated data)입니다. v1의 private ingress 계층은 제거됩니다.
- 원본 Petclinic의 JSP/폼 UI를 그대로 유지합니다. REST/SPA로 재작성하지 않았습니다.
- `ingress-nginx`는 사용하지 않고 **AWS Load Balancer Controller**로 ALB를 선언적으로 관리합니다.

---

## 2. 실제 동작 확인 결과 (실측)

### v2 — 현재 배포 (2026-10-22 컷오버)

| 항목 | 결과 |
|---|---|
| `GET https://clinic.<도메인>/` | **200** — `<title>PetClinic :: a Spring Framework demonstration</title>` |
| `GET /vets.json` | **200** — RDS 실제 데이터 반환 |
| `GET http://clinic.<도메인>/` | **301** → `https://clinic.<도메인>:443/` |
| TLS 인증서 | **ISSUED** (CN = `clinic.<도메인>`, ACM, 유효기간 2026-10-22 ~ 2027-05-07) |
| ALB | **internet-facing**, public 서브넷 2개, 타깃 **2/2 healthy** |
| WAF 연결 | `GetWebACLForResource` → `petclinic-dev-alb-waf` **연결 확인** |
| WAF 차단 | SQLi · XSS · Log4Shell → **403** / 정상 `GET /vets.json` → **200** |
| WAF 로그 | `aws-waf-logs-petclinic-dev` 에 `BLOCK` 이벤트 기록 |
| Pod | `app` 2/2, `web` 2/2 **Running** |
| RDS | **available**, Multi-AZ `true`, `PubliclyAccessible=false`, 암호화 `true` |

### v1 — 구축 이력 (API Gateway + VPC Link V2)

| 항목 | 결과 |
|---|---|
| `GET /` | **200** — `<title>PetClinic :: a Spring Framework demonstration</title>` |
| `GET /vets.json` | **200** — RDS 실제 데이터 반환 |
| `GET /vets.xml` · `/owners/find` · 정적 CSS | **200** |
| TLS 인증서 | **ISSUED** (CN = `clinic.<도메인>`, ACM, 검증 통과) |
| VPC Link V2 | **AVAILABLE** |
| internal ALB 타깃 | Web Pod 2개 **healthy** |
| EKS 클러스터 / 노드그룹 | **ACTIVE** / `web-system`·`app` 모두 **ACTIVE** |
| Pod | `app` 2/2, `web` 2/2 **Running** |
| RDS | **available**, Multi-AZ `true`, `PubliclyAccessible=false`, 암호화 `true` |
| Web 8080 `/health/*` | **404** (업무 포트로 health 미노출) |
| Web 8081 `/health/ready` | **200 `ok`** |

---

## 3. 구성 요소

### 네트워크 — 3계층 서브넷 (v2)

| 계층 | CIDR (AZ-a / AZ-b) | 용도 |
|---|---|---|
| Public | `10.20.0.0/24` / `10.20.1.0/24` | Internet Gateway, **Regional NAT Gateway 1개**(VPC 단위), **internet-facing ALB** |
| Private workloads | `10.20.32.0/20` / `10.20.48.0/20` | EKS 노드 / VPC CNI Pod IP |
| Isolated data | `10.20.80.0/24` / `10.20.81.0/24` | RDS. **인터넷 기본 경로 없음(VPC local 라우팅만)** |

> v1의 `Private ingress 10.20.8.0/24 · 10.20.9.0/24` 는 VPC Link ENI 전용이었고 **v2에서 제거했습니다**(서브넷·라우팅 연결 삭제 완료).

VPC endpoint: S3 Gateway + interface 9종(ecr.api, ecr.dkr, sts, secretsmanager, logs, eks-auth, ssm, ssmmessages, ec2messages)
> **NAT:** zonal NAT Gateway 2개 → **Regional NAT Gateway 1개**(`availability_mode = "regional"`, `vpc_id`로 생성, Subnet 소속 없음)로 전환했습니다(2026-10-23). AZ↔EIP는 `availability_zone_address`로 명시해 AWS 자동 프로비저닝 EIP를 쓰지 않습니다(미지정 시 자동 모드가 자체 EIP를 만들어 넘긴 `allocation_id`를 무시하는 것을 실측 확인). AZ 확장 시 NAT 추가가 불필요한 대신 **blast radius = VPC 전체**이며, 기존 EIP를 재사용했으므로 전환 중 egress 공백이 있었습니다. `nat_gateway_mode = "zonal"`로 이전 방식도 선택 가능합니다.

### 진입 · 보호 (v2)

| 항목 | 방식 |
|---|---|
| ALB | **internet-facing**, public 서브넷 2개 AZ, `target-type=ip`, HTTPS 443 + HTTP 80→443 리다이렉트 |
| Target group | Web Pod 8080, health check 8081 `/health/ready`, `success-codes 200` |
| AWS WAF | Regional WebACL을 ALB에 association. `AWSManagedRulesCommonRuleSet`·`SQLi` 규칙 + IP rate-based(5분/2,000) |
| 인증 | **Spring Security 폼 로그인 + DB 계정 + Spring Session JDBC** (Cognito 미사용) |
| 로그 | ALB 액세스 로그 + WAF 로그(본문 미수집, 쿠키 마스킹, sampled requests 비활성) |

### 컴퓨트 · 데이터

| 리소스 | 사양 |
|---|---|
| EKS | Kubernetes **1.34**, **private endpoint 전용**, control plane 로그(api/audit/authenticator) |
| Managed Node Group | `web-system` 2대 / `app` 2대 (`m6i.large`, AL2023, gp3 30GiB, IMDSv2, 비-root) |
| addon | vpc-cni(**NetworkPolicy ON**), kube-proxy, coredns, eks-pod-identity-agent, aws-ebs-csi-driver |
| RDS | MySQL **8.4.6**, `db.m6g.large`, **Multi-AZ**, 100GiB gp3, 백업 7일, 삭제 보호 |
| ECR | `petclinic-app`, `petclinic-web` — **IMMUTABLE** 태그, KMS 암호화, scan-on-push, lifecycle |

### 보안 · 비밀

| 항목 | 방식 |
|---|---|
| 노드 IAM | worker + CNI + ECR read + SSM. **DB 비밀 읽기 권한은 주지 않음** |
| IRSA | 5개 역할 분리 — `lbc`, `ebs-csi`, `cluster-autoscaler`, `app`, `migration` |
| DB 마스터 | **RDS 관리형 Secret** (Terraform state에 평문 없음) |
| 앱/마이그레이션 계정 | `ephemeral` + write-only 인자 → Secrets Manager. **state 평문 없음(검증 완료)** |
| EKS 시크릿 | KMS `alias/<prefix>-main` 로 envelope encryption |
| 관리 접근 | 관리 EC2(**public IP 없음, SSH 키 없음**) + **SSM Session Manager** |
| Pod 보안 | namespace PSA **restricted**, non-root, seccomp RuntimeDefault, capability drop |

---

## 4. 저장소 구조

```text
.
├── README.md
├── .gitignore                      # state·tfvars·키 제외
├── terraform/                      # foundation (v2: 3계층 VPC + WAF)
│   ├── versions.tf providers.tf variables.tf locals.tf
│   ├── network.tf security.tf kms.tf iam.tf ecr.tf eks.tf rds.tf
│   ├── oidc.tf secrets.tf waf.tf dns.tf budget.tf compute.tf
│   ├── addons.tf outputs.tf
│   ├── terraform.tfvars.example    # 복사해서 terraform.tfvars 로 사용
│   ├── modules/{network,security,eks,rds}/
│   ├── policies/aws-load-balancer-controller-iam-policy.json
│   └── templates/management-userdata.sh.tftpl
├── terraform/dns/                  # v2: ALB → Route 53 A(alias)
│   └── versions.tf providers.tf variables.tf main.tf outputs.tf
├── terraform/edge/                 # v1 전용 (destroy 완료 — 10개 리소스 삭제)
│   └── README.md                   # 전환 순서 기록
├── k8s/
│   ├── 00-namespace.yaml           # PSA restricted
│   ├── 10-app.yaml                 # SA(IRSA) + Deployment + Service + PDB
│   ├── 20-web.yaml                 # Nginx Deployment + Service + PDB
│   ├── 30-ingress.yaml             # internet-facing ALB + WAF Ingress (플레이스홀더)
│   └── render-ingress.sh           # 플레이스홀더 → terraform output 실제값 치환
├── app/
│   ├── Dockerfile                  # Tomcat 11 + ROOT.war, UID 10001
│   ├── entrypoint.sh               # 외부 설정 파일 강제, fail-fast
│   ├── Dockerfile.web              # nginx 1.29-alpine, UID 101
│   └── nginx.conf                  # 8080 업무 / 8081 health 분리
├── diagrams/
│   └── build_topology.mjs          # drawio-ai-kit 로 토폴로지 재생성
└── docs/
    ├── API_Gateway_EKS_3Tier_Phase_설계안.md
    ├── 구축_결과.md
    ├── 보류항목_추가구현_계획.md
    ├── 자료_검토_및_출처.md
    ├── 노션_페이지_확인_목록.md
    ├── 00_문서_안내.md
    └── 아키텍처_토폴로지.drawio
```

---

## 5. 사전 요구사항

| 도구 | 검증한 버전 |
|---|---|
| Terraform | **1.17.0** (AWS provider 6.70.0) |
| AWS CLI | 2.36.32 |
| kubectl | 1.36.5 |
| Helm | 3.19.0 |
| Docker | 29.1.3 |
| JDK | Temurin **21** |
| session-manager-plugin | 1.2.896.0 |

빌드 도구: Maven 3.9.16(wrapper), Tomcat **11.0.18**, nginx **1.29-alpine**

---

## 6. 배포 절차

### 6-1. 변수 파일 준비

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
#   region / cluster_name / 도메인 / DB 사양 / 태그를 환경에 맞게 수정

# v1 전용이던 terraform/edge (VPC Link + API Gateway) 는 v2에서 폐기·destroy 완료했다. 6-8 참고.
```

### 6-2. foundation 배포 (약 35~45분)

```bash
cd terraform
terraform init
terraform apply          # VPC·EKS·RDS Multi-AZ 생성
```

### 6-3. 클러스터 접근 (private endpoint)

EKS API가 private이므로 관리 EC2를 경유해 SSM 포트포워딩을 사용합니다.

```bash
# 관리 인스턴스 ID 확인
aws ec2 describe-instances --filters "Name=tag:Name,Values=*management*" \
  --query 'Reservations[].Instances[].InstanceId' --output text

# 로컬 6443 → EKS API 443
aws ssm start-session --target <INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<CLUSTER_ENDPOINT_HOST>"],"portNumber":["443"],"localPortNumber":["6443"]}'
```

kubeconfig은 `server: https://127.0.0.1:6443` + `tls-server-name: <CLUSTER_ENDPOINT_HOST>` 조합으로 만듭니다.

### 6-4. 플랫폼 addon

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=<CLUSTER> --set region=<REGION> --set vpcId=<VPC_ID> \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=<LBC_ROLE_ARN>" \
  --set replicaCount=2 --wait

helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system --set args[0]=--kubelet-insecure-tls --set replicas=2 --wait
```

### 6-5. 이미지 빌드 · 푸시

```bash
# 원본 Petclinic 소스에서
./mvnw -B -P MySQL clean package -DskipTests     # target/petclinic.war

docker build -f app/Dockerfile     -t <ECR>/petclinic-app:<TAG> .
docker build -f app/Dockerfile.web -t <ECR>/petclinic-web:<TAG> .

aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <ECR>
docker push <ECR>/petclinic-app:<TAG>
docker push <ECR>/petclinic-web:<TAG>
```

### 6-6. DB 부트스트랩

관리 EC2에서 Secrets Manager의 앱/마이그레이션 자격증명을 읽어 계정과 스키마를 만듭니다.

```sql
CREATE DATABASE IF NOT EXISTS petclinic CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'petclinic_app'@'%'      IDENTIFIED BY '<app-pw>';
CREATE USER IF NOT EXISTS 'petclinic_migrator'@'%' IDENTIFIED BY '<migrator-pw>';
GRANT SELECT, INSERT, UPDATE, DELETE ON petclinic.* TO 'petclinic_app'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
      ON petclinic.* TO 'petclinic_migrator'@'%';
```

이후 `schema.sql` / `data.sql`을 **migration 계정으로 1회** 적용합니다(멱등).

### 6-7. 워크로드 · Ingress (v2: internet-facing ALB)

```bash
kubectl apply -f k8s/00-namespace.yaml

# 앱 설정 파일(외부 주입) — 실제 값은 Secrets Manager에서 가져온다
kubectl -n petclinic-dev create secret generic app-config \
  --from-literal=data-access.properties="$(cat data-access.properties)"

kubectl apply -f k8s/10-app.yaml -f k8s/20-web.yaml

# Ingress: scheme=internet-facing, public 서브넷, ACM 인증서, WAF annotation, 80→443 리다이렉트
#   공개 저장소에는 계정 ID 가 들어간 ACM/WAF ARN 을 둘 수 없으므로 플레이스홀더를 렌더링해서 적용한다.
./k8s/render-ingress.sh                        # → k8s/30-ingress.rendered.yaml 생성
kubectl apply -f k8s/30-ingress.rendered.yaml
```

> v1에서는 internal ALB 뒤에 `terraform/edge`(VPC Link V2 + API Gateway HTTP API)를 추가로 배포했습니다.
> **v2에서는 `terraform/edge`를 폐기(destroy 완료)** 했고 ALB가 곧 외부 진입점입니다.

### 6-8. WAF 연결 · 커스텀 도메인 (v2) — **2026-10-22 완료**

1. Route53 호스티드 존 생성 후 **등록기관에서 NS 위임** ✅
2. `terraform/terraform.tfvars`: `enable_custom_domain = true` → ACM DNS 검증 → **ISSUED** ✅
3. Ingress에 `certificate-arn`, `listen-ports`(HTTPS 443 + HTTP 80), `ssl-redirect: "443"` 적용 ✅
4. **WAF WebACL(Terraform 소유)을 Ingress annotation `alb.ingress.kubernetes.io/wafv2-acl-arn` 으로 넘겨 AWS Load Balancer Controller 가 ALB 에 association** ✅
   (WebACL은 Terraform이, ALB는 LBC가 소유 — 같은 리소스를 이중 소유하지 않는다)
5. `clinic.<도메인>` → ALB A(alias) 레코드 생성 (`terraform/dns/`) ✅

> WAF 관리형 규칙은 오탐 가능성이 있으므로 **초기에는 count 모드**로 관측한 뒤 block으로 전환합니다.
> 현재는 **전부 block 모드**이며 오탐 관측은 아직 하지 않았습니다.

---

## 7. 원본 소스에서 고친 것

원본 [spring-petclinic/spring-framework-petclinic](https://github.com/spring-petclinic/spring-framework-petclinic) 을 그대로 컨테이너화하면 동작하지 않는 지점이 있어 아래를 수정했습니다. **원본 저장소는 변경하지 않았습니다.**

| # | 문제 | 수정 |
|---|---|---|
| 1 | `MySQL` 프로파일이 `mysql:mysql-connector-java:8.1.0` 참조 → Maven Central에 없음(좌표 변경됨) | `com.mysql:mysql-connector-j:9.4.0` |
| 2 | **Maven 리소스 필터링이 Spring XML의 `${jdbc.url}`을 빌드 시점에 `localhost`로 치환** → 어떤 외부 설정도 적용 불가 | `*.xml`을 filtering 대상에서 제외 |
| 3 | `business-config.xml`에 classpath 설정을 보는 placeholder가 중복 존재 | 외부 파일(`file:/etc/petclinic/...`)로 통일 |
| 4 | 기동마다 `jdbc:initialize-database`가 스키마/시드 실행 → replica마다 중복 | `noop.sql`(`SELECT 1;`)로 startup 초기화 차단 |
| 5 | Secret 미주입 시 classpath 기본값(localhost)으로 조용히 기동 | entrypoint에서 설정 파일 부재 시 **exit 1** (fail-fast) |
| 6 | 셸 특수문자 포함 DB 비밀번호가 `catalina.sh`의 `eval`을 깨뜨림 | 비밀번호를 셸 옵션이 아니라 **파일**로만 전달 |
| 7 | 공식 Tomcat 이미지에 비-root 사용자 없음 | UID/GID 10001 생성, 쓰기 경로 소유권 부여 |

---

## 8. 보안 · 비밀 관리 원칙

- **비밀은 이미지·Git·Terraform state에 넣지 않습니다.**
  앱 자격증명은 `ephemeral` + write-only 인자로 Secrets Manager에 기록하고, 마스터는 RDS 관리형 Secret을 씁니다.
- 런타임 설정은 `/etc/petclinic/data-access.properties` **파일로만** 주입하며, 없으면 기동을 거부합니다.
- `.gitignore`가 `*.tfstate*`, `terraform.tfvars`, `*.pem`, `*.key`, `kubeconfig` 등을 제외합니다.
  **이 저장소의 `*.tfvars.example` 은 플레이스홀더만 담고 있습니다.**
- 저장소에 포함된 매니페스트의 `<...>` 자리표시자는 실제 환경 값으로 바꿔 사용하세요.

> ⚠️ 이 저장소의 코드는 **학습·데모 목적**입니다. 운영에 사용할 경우 Terraform state를 S3+DynamoDB로 이전하고, 인증(아래 9번)을 먼저 적용하세요.

---

## 9. 아직 구현하지 않은 것

`docs/보류항목_추가구현_계획.md`에 항목별 선행조건·구현 방법·완료 판정 기준을 정리해 두었습니다.

| ID | 항목 | 상태 |
|---|---|---|
| D1 | HTTPS · 커스텀 도메인 | ✅ 완료 (ACM ISSUED, `clinic.<도메인>` 200) |
| D2 | NetworkPolicy default-deny | 미적용 (VPC CNI 기능은 ON) |
| D3 | migration Job | 관리 EC2에서 1회 적용 (Job화 미완) |
| D4 | 앱 `/health/live`·`/ready` | 미구현 (`/`·TCP probe로 대체 중) |
| D5 | HPA + Cluster Autoscaler | metrics-server만 설치, IRSA 역할 준비됨 |
| D6 | **폼 로그인 인증·인가·CSRF·공유 세션** (Cognito 제거) | **미구현 — UI가 무인증 상태이므로 공개 서비스로 사용 금지** |
| D7 | Secrets Store CSI Driver | K8s Secret 파일 마운트로 대체 중 |
| D8 | 부하·장애·복구 시험 | 미수행 |
| D9 | Terraform state 원격화 | 로컬 state |

### 의도적으로 넣지 않은 것 (미구현 아님)

아래 둘은 빠뜨린 항목이 아니라 **선택의 결과**입니다.

| 항목 | 왜 없는가 |
|---|---|
| EKS 컨트롤 플레인 | `aws_eks_cluster`가 클러스터 생성 시 자동으로 만든다(끄는 인자 없음). 문서·토폴로지의 밴드는 IRSA 신뢰(OIDC issuer)·private endpoint ENI가 우리 서브넷에 주입되는 사실·클러스터 시간 과금을 설명하기 위해 유지한다 |
| Gateway API 구현체 (NGINX Gateway Fabric 등) | L7은 internet-facing ALB가 담당하고 Ingress는 `ingressClassName: alb`다. LBC는 Ingress를 읽어 ALB를 만들 뿐 데이터 경로에 없으며, 구현체를 넣으면 NLB 경유가 되어 **WAF를 붙일 수 없다**. Gateway API 표준 준수나 멀티클러스터 라우팅이 요건이 될 때만 `CloudFront(WAF) → NLB → NGF`로 재설계한다 |

---

## 10. 비용 주의

이 구성은 **실제 과금되는 리소스**를 만듭니다. EKS control plane, 노드 4대, **RDS Multi-AZ**, Regional NAT Gateway 1개, interface VPC endpoint 9개, **internet-facing ALB + AWS WAF**, CloudWatch Logs, ECR, KMS가 계속 과금됩니다.

- 모든 리소스에 `Project / Environment / Owner / ExpiresAt` 태그를 부여합니다(`terraform.tfvars`에서 설정).
- Budget 알림은 **자동 비용 상한이 아닙니다.**
- **정리 순서는 `terraform/dns` → Ingress → foundation 이다.** `terraform/dns`가 `data.aws_lb`로 ALB를 조회하므로, ALB가 먼저 사라지면 destroy 계획이 실패한다.

```bash
# 1) dns 먼저 (ALB 가 살아있을 때)
cd terraform/dns && terraform destroy
# 2) Ingress 삭제 → LBC 가 ALB/TG 삭제를 끝낼 때까지 확인
kubectl -n petclinic-dev delete ingress petclinic-web
aws elbv2 describe-load-balancers          # 0개 확인
# 3) 워크로드 · Helm
kubectl delete namespace petclinic-dev
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall metrics-server -n kube-system
# 4) RDS 삭제 보호 해제 → foundation destroy
#    tfvars: db_deletion_protection=false / db_skip_final_snapshot=true 로 바꾸고 apply 후 destroy
cd terraform && terraform apply && terraform destroy
```

**Terraform 밖에서 손으로 지워야 하는 것** (실제 해체에서 확인):

| 리소스 | 그대로 두면 | 처리 |
|---|---|---|
| ECR 안의 이미지 | `RepositoryNotEmptyException` | `aws ecr delete-repository --force` |
| 노드 종료 후 남은 ENI | subnet·SG `DependencyViolation` | ENI 삭제 |
| EKS 관리형 `eks-cluster-sg-*` | VPC `DependencyViolation` | SG 수동 삭제 |
| RDS 자동 스냅샷 | 7일 보관·과금 | `aws rds delete-db-instance-automated-backup` |
| RDS 로그 그룹 2개 | 계속 과금 | `aws logs delete-log-group` |
| KMS 키 | 즉시 삭제 불가 | `PendingDeletion` 만료 대기 |
| Route 53 호스티드 존 | 도메인 NS 위임이 끊김 | 유지하려면 destroy 전에 분리 |

---

## 11. 문서

| 문서 | 내용 |
|---|---|
| [설계안](docs/API_Gateway_EKS_3Tier_Phase_설계안.md) | 아키텍처·네트워크·인증·DB 계약, Phase 0~10, 인수 테스트 14개, 비용·정리 |
| [구축 결과](docs/구축_결과.md) | 실제 생성 리소스, 검증 결과, 설계와 다르게 적용한 부분, 해결한 장애, 재현 절차 |
| [보류 항목 추가 구현 계획](docs/보류항목_추가구현_계획.md) | 미구현 9개 항목의 구현 방법·완료 판정·위험 |
| [자료 검토 및 출처](docs/자료_검토_및_출처.md) | 참고 자료와 실제 소스의 차이, 적용·제외 판단 |
| [아키텍처 토폴로지](docs/아키텍처_토폴로지.drawio) | draw.io 다이어그램 (다이어그램 편집기로 열기) |
| [5일 스터디 커리큘럼](docs/5일_스터디_커리큘럼.md) | **EC2 3-tier 경험자용** Docker/Kubernetes 흐름 학습 계획 (5일). 클러스터→노드→Pod→Service→Ingress 흐름을 EC2 개념과 짝지어 설명 |

토폴로지 재생성:

```bash
npm i drawio-ai-kit
npx drawio-ai run diagrams/build_topology.mjs
```

---

## 12. 참고

- 애플리케이션: [spring-petclinic/spring-framework-petclinic](https://github.com/spring-petclinic/spring-framework-petclinic) (Spring Framework 7 기반 JSP MVC WAR)
- 다이어그램: [sparklabx/drawio-ai-kit](https://github.com/sparklabx/drawio-ai-kit)
- `ingress-nginx`는 2026년 3월 유지보수 종료 공지에 따라 사용하지 않았습니다.
