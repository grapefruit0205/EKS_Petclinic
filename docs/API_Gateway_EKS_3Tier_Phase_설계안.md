# Amazon EKS 기반 Petclinic 3-Tier 구축 설계안 (v2)

> 작성 기준일: 2026-10-22\
> 문서 상태: **구축 전 설계안**. AWS 리소스 생성, 애플리케이션 변경, 빌드·배포·부하 테스트를 수행한 결과물이 아니다.\
> 대상 소스: [`spring-petclinic/spring-framework-petclinic`](https://github.com/spring-petclinic/spring-framework-petclinic), 기준 커밋 [`cf392920cdbe9cd07689f1f4b603271940bac957`](https://github.com/spring-petclinic/spring-framework-petclinic/commit/cf392920cdbe9cd07689f1f4b603271940bac957).\
> 근거와 자료의 제한사항: [자료 검토 및 출처](자료_검토_및_출처.md), [노션 페이지 확인 목록](노션_페이지_확인_목록.md).

## 0. v2 개정 요약

| 구분 | 개정 내용 |
|---|---|
| 제거 | Amazon API Gateway HTTP API, VPC Link V2, internal ALB, Amazon Cognito(User Pool/앱 클라이언트/Hosted UI), private ingress 서브넷(`10.20.8.0/24`, `10.20.9.0/24`) |
| 채택 | internet-facing ALB 직접 진입, AWS WAF Regional WebACL |
| 유지 | EKS·RDS·ECR·IRSA·Route 53·ACM, Nginx Web·Spring MVC App·Data의 3-Tier |
| 영향 | VPC 4→3계층, 보안 그룹 단순화, 요청·연결 계층 제거에 따른 비용 구조 변화 |
| 후속 조정 | NAT를 AZ별 zonal 2개 → **Regional NAT Gateway 1개**(VPC 단위, AZ 자동 프로비저닝, EIP는 AZ별 명시)로 전환. 구축 후 적용한 변경이며 §4.1·§5.1·§10.1·§10.3에 반영 |
| 설명 보강 | 컨트롤 플레인·데이터 플레인의 소유 경계(§7.3)와 L7 진입 계층에서 Gateway API 구현체를 채택하지 않는 근거(§7.4)를 추가. §7.2 도구 표의 폐기된 `terraform/edge` 표기를 `waf`+`dns`로 정정 |

파일명은 v1 기준이며 이력 보존을 위해 유지한다. 이 문서는 v2의 구축 전 설계안이며 실제 구축·검증 결과를 나타내지 않는다.

## 1. 목표와 범위

### 1.1 목표

첨부 PDF의 Web/WAS/RDS 구성을 발전시켜, **AWS WAF를 연결한 internet-facing ALB를 애플리케이션 외부 진입점으로 사용하고 EKS의 Web·App 계층과 RDS의 Data 계층을 분리**한다. 컨테이너 실행 성공뿐 아니라 재현 가능한 배포, 권한 통제, 다중 AZ 운영, 관측, 장애 복구까지 검증 가능한 프로젝트로 만든다.

- 사용자 기능: 보호자 검색·등록·수정, 반려동물 등록·수정, 진료 방문 등록, 수의사 조회.
- 원본 JSP/Spring MVC 화면과 폼을 유지한다. ALB는 HTML·정적 자산·폼·JSON/XML을 Web으로 전달한다.
- 배포 3-Tier는 **Nginx Web → Spring MVC App → RDS MySQL**이다. ALB와 WAF는 진입·보호 인프라이며 별도 업무 Tier로 세지 않는다.
- 소스 내부의 presentation/service/repository **논리 3-layer**, 배포 환경의 **3-tier**, 독립 서비스 분해인 **MSA**는 다르다. 이번 기본안은 모놀리식 Petclinic의 3-tier 운영이지 MSA 전환이 아니다.

### 1.2 기본안과 제외 범위

| 구분 | 기본 구축 범위 | 기본안에서 제외하거나 후속으로 분리 |
|---|---|---|
| 진입 | internet-facing ALB + AWS WAF Regional WebACL | API Gateway HTTP API, VPC Link V2, internal ALB, private ingress 서브넷, 불필요한 NLB 중첩 |
| 실행 | EKS Managed Node Group, AWS Load Balancer Controller, Nginx Web, Tomcat App | EKS Auto Mode 동시 사용, ingress-nginx 신규 설치 |
| 데이터 | RDS MySQL, 런타임 설정 외부화, 버전 관리 마이그레이션 | 운영 DB를 EKS Pod/PVC로 운영, Pod 로컬 H2 |
| 배포 | Terraform + Helm + GitHub Actions + Argo CD | 콘솔 수작업만으로 운영, `latest` 의존 |
| 보안 | Spring Security 폼 로그인 + DB 계정 + Spring Session JDBC, 인가·CSRF | Cognito(User Pool/앱 클라이언트/Hosted UI), 원본 CRUD의 무인증 인터넷 공개 |
| 확장 | HPA + Cluster Autoscaler, 다중 AZ, PDB | Cluster Autoscaler와 Karpenter의 동일 노드그룹 중복 관리 |
| 관측 | CloudWatch 로그·지표·알람, 앱/JVM 계측 | 모든 관측 제품의 동시 설치 |
| 보호 범위 | Regional WebACL을 ALB에 직접 연결 | AWS WAF는 CloudFront/API Gateway(지원 REST API stage)에도 연결할 수 있으나 이번 설계에서 제외 |
| 후속 선택 | REST API 확장, 정적 콘텐츠 CDN, 세밀한 카나리, OIDC/외부 IdP | 처음부터 SPA 재작성·서비스 메시·멀티 리전 도입 |

**가정:** 서울 `ap-northeast-2`, 단일 AWS 계정·리전의 dev부터 시작한다. 운영 목표는 2개 AZ이며, 실제 AZ 이름과 AZ ID를 계정에서 확인한다. 도메인 소유권, 예산, 인원, 목표 부하는 Phase 0에서 확정한다. 아래 용량과 일정은 제안값이지 측정 결과가 아니다.

## 2. 자료 대조 결과와 반드시 수정할 점

| 확인한 사실 | 설계에 미치는 영향 |
|---|---|
| GitHub 원본은 Spring Boot가 아닌 **Spring Framework 7 기반 JSP MVC WAR** | `java -jar app.jar`, Boot 전용 환경변수, 기본 Actuator를 전제로 설계하지 않는다. |
| POM은 Java 17 이상, Maven 3.8.4 이상; wrapper는 3.9.16 | 프로젝트 실행 기준은 **JDK 21 + 호환 Tomcat 11.x**를 후보로 정하고 Phase 1에서 검증한다. |
| POM에 Servlet 6.1/Tomcat 11 계열과 Jetty 11 실행·Jib 설정이 함께 존재 | README 명령·공개 이미지를 그대로 운영 승인하지 않는다. 런타임 호환성 검증을 최우선으로 둔다. |
| 실제 산출물은 `target/petclinic.war` | 컨테이너에는 `ROOT.war`로 배포해 외부 `/`와 내부 context `/`를 일치시킨다. |
| Maven 기본 DB는 인메모리 H2 | 운영 이미지는 `-P MySQL`로 JDBC 드라이버를 포함하고 RDS를 사용한다. |
| `datasource-config.xml`이 앱 시작마다 schema/data SQL 실행 | startup 초기화를 운영에서 차단하고 별도 migration Job으로 분리한다. Pod 수 증가로 DDL/seed가 반복되면 안 된다. |
| 실제 설정은 `jdbc.*`; PDF의 `db.url/db.user/db.pw`는 다른 포크 예시 | 설정 키를 원본에 맞춘다. `SPRING_DATASOURCE_*`가 자동 동작한다고 가정하지 않는다. |
| HTML 폼 중심이며 `/vets.json`, `/vets.xml`만 일부 읽기 데이터 엔드포인트 제공 | `/api/**`만 열어서는 원본 UI가 동작하지 않는다. 전체 UI 경로를 프록시한다. |
| 원본에 인증, 전용 health endpoint, 공유 세션 설정이 없음 | 보안·프로브는 **새로 구현할 항목**이다. 구현 전 공개 서비스를 승인하지 않는다. |
| 원본은 업무 세션과 파일 업로드 의존성이 확인되지 않음 | Redis·EFS는 원본 실행의 필수 구성요소가 아니다. 인증을 추가할 때 공유 세션을 설계한다. |
| PDF는 NLB + ingress-nginx를 사용하고 향후 ALB/IaC 전환을 제안 | internet-facing ALB + AWS Load Balancer Controller, Terraform/Helm을 기본으로 채택한다. |
| ingress-nginx는 공식 공지상 2026년 3월 유지보수 종료 | **ingress-nginx 컨트롤러는 사용하지 않는다.** 일반 Nginx Web 서버와 Kubernetes Ingress API 자체의 종료를 뜻하지 않는다. |

PDF의 평문 DB 인증정보, 장기 액세스 키 저장, Tomcat manager/host-manager 접근 개방, mutable `latest`, 오래된 이미지 버전, 무료 비용 가정은 재사용하지 않는다. 실제 자격증명이었던 값이 있다면 소유자가 폐기·교체하고 저장소 이력과 이미지 레이어까지 점검해야 한다.

## 3. 목표 아키텍처

### 3.1 요청 경로

```text
사용자 브라우저
  │ HTTPS 443 (clinic.<도메인>, 예: clinic.example.com)
  ▼
Route 53 (A alias) ── ACM 인증서(ap-northeast-2, Regional)
  ▼
Internet-facing ALB (public 서브넷 2개 AZ, scheme=internet-facing)
  │ ← AWS WAF (Regional WebACL 연결)
  │ target-type: ip
  ▼
Tier 1: Nginx Web Deployment (EKS, 2+ replicas, 8080 업무 / 8081 health)
  │ app-svc:8080 (ClusterIP + Service DNS)
  ▼
Tier 2: Spring MVC / Tomcat App Deployment (EKS, 2+ replicas)
  │ JDBC + TLS, TCP 3306
  ▼
Tier 3: RDS MySQL 8.4.6 (isolated data 서브넷, Multi-AZ)

제어 흐름: AWS Load Balancer Controller → ALB/Target Group 설정
배포 흐름: GitHub Actions → ECR + 배포 Git → Argo CD → EKS
```

- ALB는 public 서브넷에 두고, EKS 노드·Pod는 private workloads, RDS는 isolated data 서브넷에 둔다.
- ALB의 IP target 모드에서는 실제 데이터가 Web Pod IP로 전달된다. `Ingress → Service → EndpointSlice`는 대상을 찾는 제어 관계이며, ALB 요청이 반드시 ClusterIP를 통과하는 것은 아니다.
- ALB 연결 설정은 `IngressClass=alb`의 Ingress로 선언한다. App Service를 직접 외부에 노출하지 않는다.
- Nginx는 별도 Web Tier를 보여주기 위해 유지한다. 독립 SPA는 아니며 동적 화면 렌더링은 App의 JSP가 담당한다. 단순화가 우선이면 향후 ALB → App도 가능하지만, 본 프로젝트의 독립 Web Tier 요구와는 구분한다.

### 3.2 각 계층의 책임

| 계층/구성 | 책임 | 하지 않는 일 |
|---|---|---|
| Internet-facing ALB | HTTPS 종료, 호스트/경로 기반 L7 라우팅, healthy Web Pod로 분산 | 사용자 로그인 상태 저장, API 키·사용량 계획·요청 검증 |
| AWS WAF | 관리형 규칙·IP 기반 과다 요청 차단, 요청 관측 | 사용자 인증·인가, 모든 공격의 완전한 차단 보장 |
| Nginx Web | 리버스 프록시, 헤더 정규화, 자체 health, 보안 헤더 | DB 접속, PHP/IMDS 조회, 업무 처리 |
| Tomcat App | MVC/JSP, 유효성 검사, 업무 로직, DB 접근, 인증·인가 | 이미지 빌드, 매 시작마다 운영 스키마 생성 |
| RDS | 업무 데이터·공유 세션 영속화, 백업, Multi-AZ failover | Web 요청 처리, Multi-AZ standby를 읽기 replica로 간주 |

초기에는 `/resources/**`, `/webjars/**`도 App으로 전달한다. 정적 파일을 Web 이미지로 분리할 때는 같은 릴리스의 자산을 배포해야 하며, 별도 CDN은 검증 후 추가한다.

## 4. 네트워크·보안 설계

### 4.1 VPC와 서브넷 제안

VPC `10.20.0.0/16` 예시. 기존 네트워크·VPN·Kubernetes Service CIDR과 충돌하지 않는지 먼저 확인한다.

| 용도 | AZ-A 예시 | AZ-B 예시 | 기본 경로/용도 |
|---|---|---|---|
| Public | `10.20.0.0/24` | `10.20.1.0/24` | IGW, internet-facing ALB. 워커·DB 배치 안 함 |
| Private workloads | `10.20.32.0/20` | `10.20.48.0/20` | EKS 노드·VPC CNI Pod IP. 기본 경로는 Regional NAT Gateway |
| Isolated data | `10.20.80.0/24` | `10.20.81.0/24` | RDS subnet group; 인터넷 기본 경로 없음(VPC local만) |

- VPC는 위 3계층으로 구성한다. Public 서브넷만 ALB 대상 태그(`kubernetes.io/role/elb=1`)/명시적 subnet ID로 선택하며 DB subnet을 자동 검색 대상에 넣지 않는다.
- ALB 확장용 IP와 노드·Pod IP 할당량을 별도로 계산한다. `/24`, `/20`은 출발점이며 무제한 확장을 보장하지 않는다.
- **NAT는 Regional NAT Gateway 1개를 기본으로 한다.** `availability-mode=regional`은 VPC 단위 리소스로 subnet에 속하지 않으며(`describe-nat-gateways`의 `SubnetId`가 비어 있음), VPC의 각 AZ에 NAT를 자동 프로비저닝한다. AZ가 늘어도 리소스를 추가하지 않는다.
- 대신 **EIP를 AZ별로 명시**해야 한다. `availability_zone_address`(Terraform `aws_nat_gateway`)를 지정하지 않으면 AWS가 EIP를 자체 생성·관리하고(자동 프로비저닝 모드) 사전에 만든 EIP는 쓰이지 않는다. AZ 수만큼 EIP를 계획하고, apply 후 주소가 우리 `eipalloc`과 일치하는지와 `auto_provision_zones`/`auto_scaling_ips`가 `disabled`인지 확인한다.
- Regional은 **blast radius가 VPC 전체**다. Zonal NAT 2개는 한 AZ의 NAT 장애가 그 AZ 경로에만 영향을 주지만, regional은 단일 리소스라 장애·설정 변경의 영향 범위가 넓다. AZ 단위 격리가 요건이면 zonal 2개를 유지한다.
- zonal → regional 전환은 **새 NAT 생성 → 라우팅 테이블 전환 → 구 NAT 삭제** 순서로 한다. 단 **기존 EIP를 재사용하면 구 zonal NAT가 먼저 주소를 놓아야** 새 NAT가 그 주소를 잡을 수 있으므로 그 사이 egress가 끊긴다. egress 무중단이 요건이면 **새 EIP를 발급**해 regional NAT에 붙이고 라우팅을 바꾼 뒤 구 NAT·구 EIP를 해제한다.
- ECR API/DKR, S3 gateway endpoint, STS, Secrets Manager, CloudWatch Logs, EKS Auth(Pod Identity), SSM 관련 endpoint를 필요한 것만 검토한다. Endpoint만 만들면 모든 외부 통신이 해결되는 것은 아니다.
- Argo CD의 Git 접근, 외부 이미지/Helm 접근에는 별도 egress가 필요하다. 지원 endpoint가 없는 목적지는 NAT/제어된 프록시 경로를 유지한다.
- EKS API endpoint는 private 기본. 관리자는 VPN 또는 private 관리 EC2의 SSM을 통해 접근한다. SSM은 적절한 NAT/VPC endpoint가 있으면 public IP 없이도 가능하다.

### 4.2 보안 그룹과 NetworkPolicy

기본 노드그룹: `web-system`과 `app`을 분리하고 각 그룹을 2 AZ에 배치한다. Web와 App은 label/taint/toleration 및 배치 정책으로 구분한다. **Node label만으로 네트워크 격리가 되지는 않는다.**

| 출발 | 도착 | 허용 | 근거 |
|---|---|---|---|
| `0.0.0.0/0` | `sg-alb` | TCP 443 | WAF 연결 ALB에서 요청 검사; SG 자체가 WAF를 구분하는 것은 아님 |
| (선택) `0.0.0.0/0` | `sg-alb` | TCP 80 | 443 리다이렉트만, 업무 응답 금지 |
| `sg-alb` | `sg-web-node` / Web Pod | TCP 8080·8081 | 업무 target 8080, 별도 health 8081 |
| Web workload | App workload | TCP 8080 | Nginx → `app-svc` |
| `sg-app-node` | `sg-rds` | TCP 3306 | 기본안의 App 전용 노드 출발 JDBC |
| 관리 경로 | EKS API | TCP 443 | IAM Access Entries + RBAC 병행 |
| 허용 workload | DNS, 필요한 AWS API/Git | DNS 53, HTTPS 443 등 | 실제 dependency별 allowlist |

- RDS에 cluster 공통 SG나 `0.0.0.0/0`를 허용하지 않는다. 기본안의 App node SG는 **Pod 단위 권한이 아님**을 인정하고 App 노드에 임의 workload를 배치할 권한을 제한한다. 더 강한 격리가 필요하면 Security Groups for Pods를 별도 검증해 적용한다.
- EKS 관리 통신, kubelet, webhook, CNI, DNS의 필수 통신 규칙은 위 업무 흐름표와 별개로 유지한다. 단순히 위 포트만 남겨 클러스터 통신을 깨뜨리지 않는다.
- VPC CNI NetworkPolicy 지원을 활성화·검증한다. namespace default-deny에서 시작해 Web → App, App → DB, DNS, 필요한 egress를 허용한다.
- ALB → Web 허용은 Pod label selector로 ALB를 표현하지 않고 ALB가 배치된 public 서브넷의 사설 IP 범위와 SG를 함께 검증한다. Node/probe 트래픽의 적용 예외도 테스트한다.
- `web` Pod → RDS, 임의 Pod → App/RDS, 인터넷 → 노드/DB는 **실패해야 성공**인 음성 테스트로 남긴다. 같은 대상의 허용 경로가 성공하는 정상 대조군을 두고 DNS·이미지 pull·테스트 명령 실패와 정책 차단을 종료 코드·흐름 관측으로 구분한다. `실패 || echo BLOCKED`만으로 통과시키지 않는다. 여러 NetworkPolicy의 허용은 합집합이므로 정책 전체와 라벨 수정 RBAC도 점검한다.
- 기본 서비스는 ClusterIP. 인터넷용 NodePort/LoadBalancer Service를 별도로 만들지 않는다. NetworkPolicy만으로 노드 관리자까지 방어한다고 주장하지 않는다.

### 4.3 IAM과 비밀 관리

- 사람: IAM Identity Center/AssumeRole, MFA, EKS Access Entries, namespace별 RBAC. 상시 cluster-admin 금지.
- CI: GitHub OIDC → 역할. trust policy의 `aud`와 repo/branch 또는 environment `sub`를 고정. 장기 AWS 키 저장 금지.
- 노드: 이미지 pull 등 노드 운영 최소 권한. App의 DB 비밀 읽기 권한을 노드 공통 역할에 주지 않는다.
- 컨트롤러: Load Balancer Controller, Cluster Autoscaler, Argo CD 관련 권한은 각각 분리. 지원 조합을 확인해 IRSA 또는 EKS Pod Identity 사용.
- DB 비밀: Secrets Manager + Secrets Store CSI Driver/AWS provider로 읽기 전용 파일 주입. 호환성 검증 후 Pod Identity 또는 IRSA를 사용하며 migration용 Secret/역할은 분리한다.
- RDS 암호를 Terraform 평문 변수·state·빌드 인자·CLI 인자·로그에 넣지 않는다. master credential은 RDS 관리 기능 등으로 보호하고 앱 계정은 승인된 bootstrap 절차로 발급한다.
- CSI 파일 rotation만으로 이미 열린 JDBC pool이 자동 갱신되지는 않는다. 파일 갱신 → 안전한 pool 재연결 또는 rolling restart → 구 credential 폐기의 순서를 실험한다.
- Kubernetes Secret을 사용하게 되는 경우에도 Base64는 암호화가 아니므로 RBAC·저장 암호화·노출 차단이 필요하다.

### 4.4 AWS WAF 설계

| 항목 | 설계값 |
|---|---|
| 배치 | `ap-northeast-2`, `scope=REGIONAL` WebACL을 ALB ARN에 연결; Terraform `aws_wafv2_web_acl_association` 사용 |
| 관리형 규칙 | `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`, `AWSManagedRulesSQLiRuleSet` |
| 과다 요청 | Rate-based rule, `aggregate_key_type=IP`, `evaluation_window_sec=300`, `limit=2000` 제안(5분당 IP 2,000 요청 초과 차단) |
| 로그 | CloudWatch Logs `aws-waf-logs-petclinic-dev`, retention 30일, 접근 권한·암호화 적용 |
| 민감값 | `Cookie`·`Authorization` 헤더를 redacted fields로 마스킹. 요청 본문은 원문 로그로 수집하지 않으며 샘플 요청 수집은 비활성화 |
| 운영 전환 | 초기 관리형 규칙은 count 모드로 오탐 관측 → 정당한 JSP 폼·한글 입력 회귀시험 → 예외 최소화 후 block 전환 |

- 관리형 규칙은 오탐 가능성이 있다. Rate-based rule도 정밀한 요청 할당량 보장이 아니므로 공유 NAT 사용자와 정상 부하에 미치는 영향을 검증한다.
- WAF 표준 로그는 요청 본문 전체를 기록하지 않는다. 본문 마스킹을 지원하지 않는 redacted fields에 본문을 지정했다고 주장하지 않으며 Web/App·별도 수집 파이프라인에서도 본문·쿠키를 제거/마스킹한다. 로그 redaction은 sampled requests에 자동 적용되지 않으므로 `sampled_requests_enabled=false`를 적용한다.
- ALB 뒤 실제 클라이언트 IP는 **신뢰 경계에서 정규화한 `X-Forwarded-For` 첫 값**으로 식별한다. ALB의 기본 append 모드에서는 사용자가 보낸 선행 값을 신뢰하지 않고, Web이 ALB에서 온 연결만 허용한 뒤 ALB가 추가한 마지막 IP를 검증해 단일 값으로 재작성한다. WAF rate 집계는 전달 헤더가 아닌 직접 접속 source IP를 사용한다.
- 공개 전 WAF association·로그·차단 규칙을 확인한다. WAF는 Spring Security 인증·인가·CSRF를 대신하지 않는다.

## 5. 애플리케이션·데이터 계약

### 5.1 원본 수정 범위

| 항목 | 변경 계획 | 완료 증거 |
|---|---|---|
| 실행 환경 | JDK 21 + Servlet 6.1 호환 Tomcat 11.x, source SHA·base digest 고정 | WAR 배포·JSP 렌더링·폼 테스트 결과 |
| root context | `petclinic.war`를 `ROOT.war`로 배포 | `/`, CSS, form action, redirect가 같은 root에서 정상 |
| 외부 설정 | XML property placeholder에 ConfigMap/Secret 파일 위치와 우선순위 명시 | 이미지 재빌드 없이 환경별 RDS 접속, Secret 미주입 시 fail-fast |
| DB 초기화 | 운영에서 `jdbc:initialize-database` 비활성화; demo/test에만 허용 | Pod 동시 재시작 시 DDL·seed 재실행 없음 |
| migration | 버전 SQL + Flyway/Liquibase Job 중 하나 선택 | schema history, 단일 실행/잠금, 재실행 안전성 |
| health | `/health/live`, `/health/ready` 신규 구현 | DB 장애 시 live 200, ready 503; 복구 후 ready 200 |
| 프록시 인식 | 신뢰 경계에서 헤더 정규화 후 filter/서블릿 설정 적용 | HTTPS Location·쿠키 정상, 내부 host 미노출 |
| 인증·인가 | Spring Security 폼 로그인 + DB `users`/`authorities`, 읽기/쓰기 역할 분리 | 비로그인 차단, 권한 부족 403, CSRF 검증 |
| 공유 세션 | Spring Session JDBC를 RDS 별도 테이블/스키마에 추가 | 로그인 후 App Pod 교체·분산에도 세션 유지 |
| 운영 계측 | 구조화 로그, request ID, JVM/HTTP/DB pool 지표 | 요청 흐름 연계와 알람 발생 확인 |

Spring Session JDBC는 **인증 도입에 따른 새 선택**이며 원본 기능이 아니다. Redis는 초기 필수에서 제외한다. 세션 정리 주기·TTL·직렬화 호환성과 세션 DB 부하를 측정하고 필요할 때 분리한다.

### 5.2 DB 설정과 초기화

- DB 엔진 설계값은 **RDS MySQL 8.4.6**이다. Phase 0에서 서울 리전·선택 인스턴스의 해당 버전 제공 여부와 JDBC driver/SQL 호환성을 확인한다. 미지원이면 생성을 보류하고 버전 ADR을 갱신한다.
- 빌드 profile `MySQL`은 DB driver/자원 선택이다. Spring profile `jpa`/`jdbc`/`spring-data-jpa`는 repository 구현 선택이다. 기본은 기존 `jpa`를 유지하되 운영 profile과 조합 시 bean 중복 여부를 확인한다.
- 실제 키는 `jdbc.url`, `jdbc.username`, `jdbc.password` 등이다. 비밀 파일을 명시적으로 읽도록 소스를 수정하고 Java system property/환경변수의 암묵적 동작에 기대지 않는다.
- MySQL schema의 CREATE/ALTER DATABASE는 bootstrap으로 분리한다. 앱 계정에는 업무에 필요한 DML 권한만, migration 계정에는 승인된 DDL 권한만 부여한다.
- 운영에서 샘플 seed를 매 배포마다 넣지 않는다. 테스트 데이터와 운영 데이터를 분리하며 실제 개인정보는 실습에 사용하지 않는다.
- JDBC TLS는 RDS CA와 hostname 검증을 포함한다. Connector/J의 `VERIFY_IDENTITY` 및 trust 설정을 검증하고 CA 교체 절차를 마련한다.
- Hibernate 자동 스키마 변경을 운영에서 금지한다. migration 실패 시 App 신규 배포를 중단한다.

**연결 수 예산 예시:** App HPA 최대 6개 × pool 10 = 60, rolling surge 1개 × 10 = 10, migration·운영·세션 별도 pool이 있다면 추가 배정. 종료 대기 Pod가 연결을 유지하는 동안에는 `replicas + maxSurge`보다 동시 연결 주체가 많을 수 있으므로 이 70개를 절대 상한으로 취급하지 않는다. 실제 drain/rollout 중 최대 연결 수를 측정하고 RDS 허용 연결 수에서 최소 20% 안전 여유를 남긴다. Spring Session이 같은 pool을 쓰는지 별도 pool을 쓰는지 실제 설정으로 계산한다. RDS Proxy는 연결 압력이 확인될 때 추가 검토하며 필수 구성으로 넣지 않는다.

### 5.3 상태와 프로브

- 업무 영속 데이터·공유 세션은 RDS에 둔다. 로컬 파일 업로드가 없으므로 EFS는 기본안에 없다.
- JSP 컴파일용 Tomcat `work`, `temp` 등은 `emptyDir`로 제공한다. `readOnlyRootFilesystem`만 켜고 쓰기 경로를 막지 않는다.
- vets의 Pod-local Caffeine 캐시는 TTL 또는 비활성화를 검토한다. `/vets.json`의 성공은 DB readiness 증거가 아니다.
- startupProbe는 느린 JVM/JSP 초기화를 허용하고, liveness는 DB 장애와 분리한다. readiness의 DB 체크는 짧은 제한시간·과도하지 않은 주기로 수행한다.
- 원본에는 Actuator가 없으므로 `/actuator/health`를 즉시 사용 가능한 경로로 적지 않는다.

### 5.4 인증·인가·세션 계약

| 항목 | 설계값 |
|---|---|
| 로그인 | 외부 IdP 없이 Spring Security 폼 로그인(`/login`), DB `users`/`authorities` 계정 조회 |
| 계정 | 승인된 관리 절차로 생성, 공개 회원가입 제외, 비밀번호는 BCrypt 등 지원 PasswordEncoder 해시로 저장 |
| 읽기 역할 | `ROLE_READER`: 업무 GET 조회 허용, 업무 등록·수정 POST 금지 |
| 쓰기 역할 | `ROLE_WRITER`: 조회 및 업무 등록·수정 허용. URL·HTTP method별 명시적 규칙, 나머지는 deny |
| CSRF | JSP 폼에 토큰 포함, 누락·변조 거부. 로그아웃도 CSRF 검증 POST 사용 |
| 세션 | Spring Session JDBC, RDS의 전용 세션 테이블, 비활성 TTL 30분 제안, 로그인 시 세션 ID 교체 |
| 쿠키 | `Secure; HttpOnly; SameSite=Lax; Path=/`, Domain 미지정(host-only) 기본 |

인증 구현 전에는 무인증 상태이므로 공개 서비스로 승인하지 않는다. 로그인 화면·필수 정적 자산만 예외로 열고 업무 URL은 인증·역할 검증을 거친다. DB 장애가 인증 우회로 이어지지 않도록 실패 시 차단하며 로그인 실패 제한도 구현한다. OIDC/외부 IdP 도입은 §10.4의 후속 선택 과제로 분리한다.

## 6. ALB 상세 설계

### 6.1 진입·TLS·라우팅

| 항목 | 설계값 |
|---|---|
| 배치 | `scheme=internet-facing`, public `10.20.0.0/24`·`10.20.1.0/24`, 2 AZ |
| 대상 | `target-type=ip`, Web Pod TCP 8080; App 직접 target 금지 |
| DNS | `clinic.example.com`(소유 도메인으로 교체), Route 53 A alias → ALB |
| ACM | `ap-northeast-2` Regional 인증서, DNS 검증; 예시 ARN `arn:aws:acm:ap-northeast-2:123456789012:certificate/11111111-2222-3333-4444-555555555555` |
| Listener | HTTPS 443 + ACM, TLS 1.2/1.3 지원 정책 `ELBSecurityPolicy-TLS13-1-2-2021-06`; HTTP 80 → HTTPS 443 `HTTP_301` redirect |
| 규칙 | canonical Host `clinic.example.com`, path `/*` → Web; 불일치 Host는 fixed-response 404 |
| WAF | Regional WebACL을 ALB에 연결(§4.4), 업무 요청 검사 |
| 액세스 로그 | S3 전용 bucket/prefix에 저장, 전송 허용 bucket policy·public access block·암호화·lifecycle 30일 적용 |

**HTTP→HTTPS 리다이렉트는 ALB에서 수행**한다. Web은 ALB에서 온 요청만 받으며 `X-Forwarded-Proto`를 허용 listener/canonical HTTPS 기준으로 정규화한다. App은 Web 신뢰 경계만 신뢰하고 사용자 임의 `Forwarded`·`X-Forwarded-*` 값을 그대로 채택하지 않는다.

ALB는 호스트/경로 기반 L7 라우팅을 제공하며 **API 키·사용량 계획·요청 검증 같은 API 관리 기능은 없다.** 필요하면 별도 계층을 추가해야 한다. WAF rate 제한도 소비자별 사용량 계획을 대신하지 않는다. ALB 액세스 로그 저장 대상은 S3로 정하며 CloudWatch 지표·알람과 구분한다.

### 6.2 Target group·health·draining

| 항목 | 초기 제안값 |
|---|---|
| 업무 target | HTTP 8080, Web Pod IP |
| ALB health check | HTTP 8081 `/health/ready`, `success-codes=200` |
| health interval / timeout | 15초 / 5초 |
| healthy / unhealthy threshold | 2회 / 2회 |
| target draining | `deregistration_delay.timeout_seconds=30` |
| 종료 연계 | `terminationGracePeriodSeconds=60` 출발, preStop/drain 전파·진행 중 요청 완료 시간 실측 후 조정 |
| ALB idle timeout | `idle_timeout.timeout_seconds=60` |
| ALB client keepalive | `client_keep_alive.seconds=3600` |
| Web keepalive | `keepalive_timeout=75s`, ALB idle timeout보다 길게 유지; App upstream keepalive 32 제안 |

- LBC Ingress annotation으로 `alb.ingress.kubernetes.io/scheme: internet-facing`, `alb.ingress.kubernetes.io/target-type: ip`, `alb.ingress.kubernetes.io/healthcheck-port: '8081'`, `alb.ingress.kubernetes.io/healthcheck-path: /health/ready`, `alb.ingress.kubernetes.io/success-codes: '200'`을 선언한다. Listener·인증서·redirect·target group 속성도 선택한 LBC 버전의 지원 형식으로 고정한다.
- Web은 업무 listener 8080과 **관리 listener 8081**을 분리한다. ALB target은 8080, health check는 8081, kubelet Web probe도 8081을 사용한다. 8081은 외부 route/Service 업무 포트로 공개하지 않는다. Web 8080에서 `/health/*`를 차단해 App의 같은 경로도 외부로 프록시하지 않는다. App probe는 kubelet이 App Pod에 직접 수행한다. Web 자체 health·App readiness·사용자 end-to-end 상태는 서로 다른 지표다.
- draining·Pod readiness·종료 대기는 함께 검증한다. 모든 target이 unhealthy일 때 ALB의 fail-open 가능성이 있으므로 health check만을 보안 차단 수단으로 사용하지 않는다.

### 6.3 경로·헤더·쿠키

- `/`, `/owners/**`, `/vets`, `/vets.json`, `/vets.xml`, `/resources/**`, `/webjars/**`와 `/login`, `/logout` 등 구현된 인증 경로를 보존한다.
- 외부 `/` = Web 프록시 `/` = Tomcat ROOT context `/`로 일치시킨다. `/prod`·`/petclinic` 접두사를 외부 경로에 섞지 않는다.
- Web은 Host를 canonical `clinic.example.com`, scheme을 HTTPS로 정규화하고 임의 사용자 `Forwarded` 값을 제거한다. App의 `Location`·form action·절대 URL에 내부 주소가 노출되지 않게 한다.
- 클라이언트 IP 정규화는 §4.4를 따른다. 요청 ID는 Web에서 생성/검증해 App 로그와 연결하고 ALB 로그의 추적 필드와도 연계한다. 사용자 입력을 그대로 로그 키로 신뢰하지 않는다.
- 인증·인가·CSRF·쿠키 정책은 §5.4를 적용한다. ALB와 Nginx stickiness로 Spring Session JDBC를 대신하지 않는다.
- 같은 도메인 사용이므로 기본 CORS는 필요 없다. 후속 SPA 분리 시에만 허용 origin/method/header를 명시한다. credential 사용 시 wildcard origin 금지.

### 6.4 시간·크기·제한

- 초기 설정 예: SQL/connection acquisition timeout 5초, App 요청 목표 20초 미만, Nginx upstream read 25초, ALB idle timeout 60초. 계층별 timeout 의미가 다르므로 실제 요청·배포 시간에 맞춰 조정한다.
- ALB HTTP 제한은 request line 16 KB, 단일 header 16 KB, 전체 request header 64 KB를 기준으로 확인한다. Nginx/Tomcat에도 허용 크기를 명시하고 큰 쿠키·한글/쿼리 인코딩을 시험한다.
- 본문 크기는 Nginx `client_max_body_size=1m`부터 검토한다. ALB 연결 WAF의 본문 검사 한도는 8 KB이므로 초과 본문의 oversize handling을 명시하고, 필요한 폼 크기·오탐을 관측해 차단 정책을 확정한다.
- 긴 작업은 비동기 Job/상태 조회로 분리하고 대용량 파일은 필요 시 S3 presigned URL을 검토한다.
- 비멱등 폼 POST에 프록시 자동 재시도를 무분별하게 적용하지 않는다. 요청 timeout 뒤 사용자 재전송의 중복 기록도 시험한다.

## 7. EKS 운영 기본값과 리소스 소유권

### 7.1 워크로드 초기값 — 부하 테스트 후 확정

| 항목 | Web | App |
|---|---|---|
| replicas | 2 | 2 |
| requests | CPU 100m / memory 128Mi | CPU 500m / memory 1Gi |
| limits 후보 | CPU 500m / memory 256Mi | CPU 1500m / memory 2Gi |
| HPA | 필요 시 2~4 | 2~6, CPU request 대비 60% 출발 |
| rollout | maxUnavailable 0 / maxSurge 1 | maxUnavailable 0 / maxSurge 1 |
| PDB | minAvailable 1 | minAvailable 1 |
| 배치 | hostname·zone topology spread | hostname·zone topology spread |
| health | 자체 live/ready | startup/live/ready 신규 구현 |

- JVM heap은 컨테이너 memory limit보다 작게 잡고 metaspace/native/thread/JSP 여유를 남긴다. requests는 스케줄링 기준이며 무제한 성능 보장이 아니다.
- metrics-server는 HPA의 선행조건이다. HPA는 Pod 수, Cluster Autoscaler는 부족한 노드 용량을 다룬다. HPA만 설치하면 노드가 자동으로 늘어나는 것은 아니다.
- 운영 초기는 각 노드그룹 최소 2노드, 총 4노드의 x86_64 2vCPU/8GiB급을 검토한다. 시스템 DaemonSet·rollout surge·AZ 장애 여유를 포함해 산정하며 인스턴스 종류는 Phase 0에서 비용·가용성으로 확정한다.
- EKS 표준 지원 중인 Kubernetes 버전, node AMI, VPC CNI/CoreDNS/kube-proxy, LBC, CSI, metrics-server 등의 호환표를 잠근다. 첨부 PDF의 1.35를 무조건 최신으로 취급하지 않는다.
- PDB는 자발적 eviction을 제한할 뿐 AZ 장애 방지 장치가 아니다. rollout 정책·graceful shutdown·ALB target draining을 따로 검증한다. drain 전에는 다른 노드/AZ의 allocatable·배치 제약·PDB와 emptyDir 손실을 확인한다. Pod가 그대로 이동하는 것이 아니라 축출 후 재생성되므로 새 Pod의 기동·연결·CRUD 성공까지 관찰한다. 강제 삭제로 PDB를 우회해 성공으로 처리하지 않는다.
- non-root, seccomp RuntimeDefault, capability drop, allowPrivilegeEscalation=false, 읽기 전용 root와 필요한 emptyDir를 적용한다. privileged/hostNetwork/hostPID의 일반 App 사용 금지. 앱 namespace에는 Pod Security Admission의 restricted 기준을 적용하고 검증한 기준 버전을 고정한다. 노드 접근이 필요한 시스템 addon은 별도 namespace와 최소 범위 예외로 관리한다.

### 7.2 IaC/배포 도구의 역할

| 도구 | 소유 리소스/업무 |
|---|---|
| Terraform `foundation` | 3계층 VPC/SG/endpoint, EKS/MNG/IAM, ECR, RDS, Secrets 메타데이터, ACM 인증서/DNS 검증, 예산 |
| Helm/Argo CD `platform` | 컨트롤러·운영 addon, namespace/RBAC 정책 |
| Helm/Argo CD `workload` | Web/App/Service/Ingress/HPA/PDB/NetworkPolicy/migration Job |
| AWS Load Balancer Controller | Ingress 선언을 읽고 ALB/listener/target group 실제 생성·조정 |
| Terraform `waf` + `dns` | WAF WebACL·association·로그는 foundation이 소유하고, LBC가 만든 ALB를 tag로 조회해 Route 53 A alias를 연결한다(v2에서 `terraform/edge` 폐기) |
| GitHub Actions | 소스 테스트, 이미지 빌드·스캔·서명, ECR push, 배포 Git의 digest 변경 PR |

**동일 ALB/listener를 Terraform과 LBC가 동시에 소유하지 않는다.** foundation → platform → workload/ALB → edge 순서로 분리한다. ALB ARN/DNS/hosted zone ID를 tag 및 이름으로 조회·검증해 edge 입력에 연결하고, ALB 교체 시 WAF association과 DNS alias를 함께 갱신한다. WAF association은 Terraform만 소유하며 Ingress의 WAF 연결 annotation과 중복 관리하지 않는다. Terraform state는 암호화·접근 제한·잠금·버전 보관을 적용한다.

GitHub runner가 private EKS API에 직접 접속할 필요 없이 Argo CD가 배포 Git을 pull하도록 한다. 초기 addon 설치·긴급 복구는 VPC 내부 관리 경로를 사용한다. Argo CD UI를 별도 무인증 public LB로 만들지 않는다.

### 7.3 컨트롤 플레인 · 데이터 플레인의 경계

`aws_eks_cluster`(`modules/eks/main.tf`)를 생성하는 순간 API Server, etcd, scheduler, controller-manager, OIDC issuer가 함께 만들어지며 이를 끄는 인자는 없다. 컨트롤 플레인은 선택 항목이 아니라 EKS를 EKS로 만드는 요소이고, 노드그룹만 남기고 컨트롤 플레인을 제거한 구성은 존재하지 않는다.

| 소유 | 대상 | 우리가 하는 일 |
|---|---|---|
| AWS | 컨트롤 플레인 — API Server, etcd, scheduler, controller-manager, OIDC issuer | 설정만 지정. 컴포넌트에 접근·패치 불가. 클러스터 시간 과금 |
| 우리 | 데이터 플레인 — MNG 4노드, kubelet, VPC CNI, addon 5종, Deployment/Service/Ingress | 버전·용량·드레인·스케줄링·장애 대응 전부 |

우리가 명시적으로 고정한 컨트롤 플레인 설정은 다음과 같다.

| 설정 | 값 |
|---|---|
| 엔드포인트 | `endpoint_private_access = true`, `endpoint_public_access`는 변수(기본 private 전용) |
| 인증 | `authentication_mode = API_AND_CONFIG_MAP` + 생성자 admin 부여 |
| 암호화 | `encryption_config` — KMS로 etcd의 Secret 암호화 |
| 로그 | `enabled_cluster_log_types` → CloudWatch 14일 보관 |
| 요금 등급 | `billing_mode` 미설정 → standard tier |

이 경계를 문서와 토폴로지에 남기는 이유는, 설명이 필요한 세 가지가 모두 컨트롤 플레인에서 유래하기 때문이다.

1. **IRSA 신뢰의 출처** — OIDC issuer가 컨트롤 플레인에 있고 ServiceAccount 토큰이 그 키로 서명된다. LBC·CSI·ExternalDNS가 AWS 권한을 얻는 경로가 여기서 시작한다.
2. **private endpoint의 실체** — 연산 자원은 AWS 소유 계정에 있으나 endpoint ENI는 우리 서브넷에 주입된다. 그래서 관리 인스턴스 SG에서 cluster SG로 가는 443 규칙이 필요하다(구축 중 이 규칙 누락으로 API 접근이 막혔다).
3. **과금 근거** — 클러스터 시간 요금은 데이터 플레인 노드 요금과 별개 항목이다.

### 7.4 L7 진입 계층 — Gateway API 구현체를 추가하지 않는 이유

L7 라우팅 주체는 "AWS ALB"와 "클러스터 내부 구현체(NGINX Gateway Fabric 등)"로 갈린다. 현재 구성은 전자이며 후자를 추가할 실익이 없다.

| 항목 | 현재 — ALB + LBC | Gateway API 구현체 추가 시 |
|---|---|---|
| L7 처리 위치 | AWS 관리형 ALB | 클러스터 내부 Pod |
| 데이터 경로 | ALB → Pod IP (`target-type: ip`) | LB → NGF Pod → Service → App Pod |
| WAF | ALB에 직접 부착 | NLB에는 부착 불가 → WAF 상실 |
| 홉 수 | 1 | 2 이상 |
| 추가로 필요한 것 | Ingress 1개 | Gateway API CRD, GatewayClass, NGF Deployment, LB Service |

LBC는 Ingress를 읽어 AWS API로 ALB를 만들 뿐 HTTP 트래픽이 지나가지 않는다. 이 클러스터에는 Gateway API CRD·GatewayClass·NGF Deployment가 없고 Ingress의 `ingressClassName`은 `alb`다. NGF를 도입하면 WAF를 유지하기 위해 CloudFront를 앞에 두는 재설계(CloudFront+WAF → NLB → NGF)가 필요하다. Gateway API 표준 준수나 멀티클러스터 라우팅이 요건이 될 때만 정당화되며, 현재 요건에는 해당하지 않으므로 채택하지 않는다.

## 8. Phase별 실행 계획

### 전체 흐름과 일정 제안

```text
P0 범위·설계 확정 → P1 원본 실행 검증 → P2 운영화·로컬 3-Tier
 → P3 AWS 기반망(3계층 VPC)·IAM·ECR → P4 RDS·Secrets → P5 EKS 플랫폼
 → P6 Web/App·RDS·internet-facing ALB → P7 WAF·TLS·도메인·안전한 공개
 → P8 CI/CD → P9 확장·관측 → P10 장애·복구·인수·정리
```

| Phase | 예상 작업일 | 선행조건 | 핵심 통과 기준 |
|---|---:|---|---|
| 0 | 1 | 자료 검토 | 범위·예산·ADR·버전 선정 원칙 승인 |
| 1 | 1~2 | P0 | 선택 JVM/Servlet에서 원본 기능 재현 |
| 2 | 3~4 | P1 | 안전한 초기화·보안·프로브를 갖춘 로컬 3-Tier |
| 3 | 1~2 | P0, 실제 생성은 P2 확인 후 권장 | 3계층 VPC·IAM·ECR·IaC 재현 |
| 4 | 1~2 | P3 | RDS TLS·migration·백업·최소권한 |
| 5 | 1~2 | P3 | healthy EKS·addon·접근 통제 |
| 6 | 1~2 | P2/P4/P5 | 시험 출발지만 허용한 internet-facing ALB 경유 Web→App→DB, 2+ replicas |
| 7 | 1~2 | P6, 인증 기능 완료 | WAF·도메인 HTTPS·폼 로그인·차단 검증 후 공개 승인 |
| 8 | 2 | P7 | commit→승인→배포→롤백 재현 |
| 9 | 1~2 | P8 | HPA/노드 확장·대시보드·알람 |
| 10 | 2~3 | P9 | 장애·복원·인수 증빙·비용 정리 |

합계 약 **15~24 작업일**의 순차 작업량이다. P4/P5 등은 병행 가능하며 팀 숙련도·인증 구현·호환성 수정에 따라 달라진다. 일정 단축을 위해 보안/데이터 검증 gate를 생략하지 않는다.

### Phase 0 — 요구사항·기준선·의사결정 확정

**목표:** 자료의 예시와 실제 적용할 사양을 구분하고 성공 기준을 합의한다.

**작업**
1. PDF/노션 검토 결과, GitHub SHA, 자료의 코드 누락·상충 항목을 출처 문서에 기록한다.
2. 지역·계정·도메인·팀 역할·예산 상한·환경(dev/prod)을 확정한다.
3. ADR 작성: internet-facing ALB + WAF, 3계층 VPC, MVC/Nginx Web 유지, RDS MySQL 8.4.6, MNG 선택, IaC 소유권, 폼 로그인/DB 계정/공유 세션 방식.
4. 후보 runtime·RDS·Kubernetes/addon 버전의 지원 기간·호환성을 확인하고 버전 잠금 목록을 만든다. AWS Pricing Calculator로 ALB 시간/LCU와 WAF WebACL 월정액·규칙·100만 요청당 단가를 포함한 서울 리전 견적을 확인한다.
5. 목표 제안: steady 20 req/s, 15분 측정, 유효 업무 요청 성공률 ≥99%, 동적 GET p95 ≤1초. 읽기 90%/쓰기 10%와 테스트 데이터량을 명시한다. 운영 SLO 99.9%는 후속 목표이며 단기 시험으로 입증했다고 쓰지 않는다.

**산출물:** 요구사항, ADR, 주소/포트표, 버전표, 비용 추정표, 시험 계획.\
**완료 조건:** 소유자와 수용 기준 확정, 비용 발생 전 승인, 민감값 없는 문서.\
**실패 대응:** 도메인/예산 미확정이면 로컬 P1/P2만 진행하고 AWS 유료 생성은 보류.

### Phase 1 — 원본 소스·런타임 적합성 검증

**목표:** 잘못된 Boot/JAR/Jetty 가정을 제거한다.

**작업**
1. fork 또는 작업 저장소에 기준 커밋을 고정하고 license/변경 이력을 유지한다.
2. JDK 21 환경에서 `./mvnw -B verify` 수행. 원본 Java 17 호환성 유지가 요구되면 CI matrix도 유지한다.
3. Servlet 6.1 지원 Tomcat 11.x에 WAR를 배포한다. Jetty 11 설정과 혼용하지 않는다.
4. `ROOT.war`, 실제 container port 8080, `/`, 보호자/반려동물/방문 폼, `/vets.json`, CSS/WebJars를 확인한다.
5. H2는 이 단계의 기능 기준선에만 사용한다. MySQL profile 빌드와 실제 MySQL 통합시험 준비를 한다.

**산출물:** 실행 호환성 보고서, 테스트 로그, 화면/HTTP 응답 증거, 수정된 빌드 기준.\
**완료 조건:** WAR 기동과 주요 기능·정적 자산·리다이렉트 정상. 단위 테스트만 성공하고 컨테이너 부팅이 실패하면 미완료.\
**실패 대응:** 런타임·의존성을 지원 조합으로 정렬한 후 재검증. 검증 안 된 공개 `latest` 이미지로 대체해 통과 처리하지 않는다.

### Phase 2 — 앱 운영화·컨테이너화·로컬 3-Tier

**목표:** AWS 이전 전에 운영 위험을 애플리케이션 수준에서 제거한다.

**작업**
1. XML 외부 설정 경로와 운영 initializer 차단을 구현한다. 외부 Secret 누락 시 임의 H2로 fallback하지 않게 한다.
2. SQL을 migration/선택적 demo seed로 분리하고 별도 migration 실행으로 전환한다.
3. 전용 live/ready, proxy 인식, 로그 마스킹·request ID, DB pool/timeout 설정을 추가한다.
4. Spring Security 폼 로그인, DB `users`/`authorities`와 비밀번호 해시, `ROLE_READER`/`ROLE_WRITER`의 URL·HTTP method별 인가, JSP CSRF, Spring Session JDBC를 구현한다. 로컬 테스트 계정으로 권한·쿠키·세션 분산을 검증한다. 인증 구현 전에는 무인증 상태이므로 공개 서비스로 승인하지 않는다.
5. App은 Maven builder → Tomcat runtime 멀티스테이지, Web은 최소 Nginx 이미지로 만든다. builder 테스트와 runtime smoke를 모두 수행한다.
6. Dockerfile에 source SHA/base digest, non-root, foreground 실행, `.dockerignore`를 적용한다. 이미지 레이어·환경변수에 비밀을 넣지 않는다.
7. Compose에서 Web만 localhost 포트 공개, App/DB는 미공개. `web-app`, `app-db` 네트워크를 분리하고 App만 양쪽에 연결한다.
8. MySQL volume 유지 상태의 컨테이너 재생성, App replica 2개, 세션 분산, DB 장애/readiness, migration 재실행을 시험한다.

**산출물:** App/Web Dockerfile, Compose, 운영 설정 코드, migration, 보안·probe 테스트, SBOM/스캔 결과.\
**완료 조건:** 새 환경에서 재현, App 재시작/동시 기동으로 데이터 변경 없음, 무인증 쓰기·CSRF 실패, 비밀 미포함.\
**실패 대응:** 이미지 이전 digest로 복구. DB는 함부로 `down -v`하지 않고 migration 실패 원인과 백업 상태부터 확인.

### Phase 3 — AWS 기반망(3계층 VPC)·IAM·ECR·예산

**목표:** IaC로 3계층 VPC와 사설 실행 기반, 권한 경계를 만든다.

**작업**
1. Terraform state backend/잠금과 CI plan 검토 절차를 먼저 준비한다.
2. VPC `10.20.0.0/16`에 §4.1의 Public/Private workloads/Isolated data 3계층·2 AZ의 총 6개 subnet, route, **Regional NAT Gateway 1개(AZ별 EIP를 명시)**, 필요 endpoint/SG/DNS를 생성한다. Public만 IGW를 연결하고 workloads는 regional NAT를 기본 경로로 쓴다. DB 서브넷은 인터넷 기본 경로 없이 VPC local만 둔다.
3. ECR `petclinic-web`, `petclinic-app`을 private·immutable tag·암호화·scan·lifecycle로 구성한다. BuildKit/buildx가 생성하는 OCI manifest index·플랫폼별 본체·provenance attestation에서 태그가 인덱스에만 붙고 참조된 하위 매니페스트는 untagged 행으로 보일 수 있으므로, 단순 "태그 없는 이미지 즉시 만료" 규칙으로 활성 태그의 하위 참조가 깨지지 않게 설계한다.
4. 관리/CI/노드/컨트롤러/비밀 접근 역할을 분리한다. GitHub OIDC trust를 repo/environment로 제한한다.
5. Secrets 메타데이터와 비용 tag(`Project`, `Environment`, `Owner`, `ExpiresAt`)를 정의하고 Budget 알림을 연결한다.
6. SSM 관리 경로, private DNS, ECR pull 네트워크를 시험한다.

**산출물:** foundation IaC, IAM matrix, ECR 정책, 네트워크/예산 증거.\
**완료 조건:** 불필요한 public IP·SSH·DB 공개 없음, 허용 주체만 접근, IaC plan 재실행에 예상 외 변경 없음.\
**실패 대응:** `terraform plan`과 state를 기준으로 해당 stack만 복구. 공용 사용자 리소스 일괄 삭제 금지.

### Phase 4 — RDS·Secrets·마이그레이션·백업

**목표:** App lifecycle과 독립적인 데이터 계층을 확보한다.

**작업**
1. DB subnet group, encrypted RDS MySQL 8.4.6, `publicly_accessible=false`, backup retention을 구성한다. 운영은 Multi-AZ, 삭제 보호와 최종 snapshot 정책을 적용한다. 버전 제공 여부는 P0 승인 목록을 따른다.
2. RDS master, migration, runtime DML 계정을 분리하고 비밀을 안전하게 발급한다.
3. 승인된 VPC 내부 관리 runner에서 RDS TLS/CA·hostname과 migration baseline을 검증한다. EKS migration Job은 P5 이후 P6에서 같은 버전 이력을 이어받는다.
4. Secrets Manager 값/접근 정책과 XML 파일 주입 계약을 준비한다. **CSI mount 및 실제 App 연결 검증은 P5 완료 후 P6의 선행 gate**로 수행한다.
5. 데이터 백업·PITR 가능 구간을 확인하고 별도 복원 DB로 실제 읽기·쓰기 검증을 수행한다.

**산출물:** DB 설계/권한표, migration 이력, Secret 주입 절차, 백업·복원 절차.\
**완료 조건:** runtime 계정으로 DDL 불가, 인터넷 DB 접근 차단, 관리 runner의 TLS 검증 및 백업 복원 성공. Web→DB 차단·App 재시작 검증은 P6에서 완료한다.\
**실패 대응:** 이전 앱과 호환되는 expand/contract schema 원칙. 파괴적 변경은 승인을 거쳐 snapshot/PITR 복구; SQL 자동 역실행을 만능 롤백으로 취급하지 않는다.

### Phase 5 — EKS 플랫폼·Addon·접근 제어

**목표:** App 배포 전에 클러스터 운영 기반을 검증한다.

**작업**
1. private EKS와 MNG를 생성하고 API access entries/RBAC를 적용한다. EKS Auto Mode를 동시에 사용하지 않는다.
2. VPC CNI, CoreDNS, kube-proxy, Pod Identity agent(채택 시), metrics-server, LBC, CSI provider, Cluster Autoscaler를 호환 버전으로 설치한다.
3. namespace `petclinic-dev`/운영 별도 환경, ServiceAccount, quota/limit, 배치 label/taint, NetworkPolicy를 구성한다.
4. 컨트롤러 AWS 권한과 webhook/API 통신, ECR pull, DNS를 시험한다. CSI는 비민감 테스트 Secret으로 mount/권한 거부를 확인한다. P4의 실제 DB Secret을 사용하는 검증은 P6에서 수행하므로 P4/P5 병행을 막지 않는다.
5. Argo CD bootstrap 및 Git 접근을 준비하되 UI를 인터넷에 직접 공개하지 않는다.

**산출물:** 플랫폼 Helm values, 접근 정책, 버전 잠금, cluster baseline 증거.\
**완료 조건:** node Ready, addon healthy, 최소권한 접근과 음성 테스트 성공, Pod IP 용량 확인.\
**실패 대응:** addon 버전 pin 복구·nodegroup 교체 계획. EKS control plane minor downgrade를 롤백 수단으로 가정하지 않는다.

### Phase 6 — Web/App·RDS 연결 및 인터넷-facing ALB

**목표:** 시험 출발지만 허용한 internet-facing ALB에서 Web→App→RDS의 3-Tier 경로를 완성한다.

**작업**
1. P4의 DB Secret을 migration/App 전용 ServiceAccount로 각각 CSI mount하고 권한·파일 경로를 먼저 검증한다. 실제 non-root UID/GID가 필요한 파일만 읽을 수 있는지 확인하며 root 소유 `0400`을 무조건 복사하지 않는다. CSI 지원 권한 설정·그룹 소유권을 검증하고 rotation 후 파일 갱신과 앱 재로딩/재연결을 각각 확인한다. 비밀 파일 내용이나 전체 env를 로그로 출력하지 않는다. migration Job을 수행한 뒤 성공한 schema version에 대해서만 App sync를 진행한다. 병렬 Job도 migration 도구 잠금으로 제어한다.
2. ECR digest로 Web/App Deployment와 ClusterIP Services를 배포한다. ConfigMap/Secret 파일, probe, resources, PDB, spread, securityContext를 적용한다.
3. Web/App 각각 replicas 2개 이상을 2 AZ에 배치한다. App은 같은 RDS와 공유 세션을 사용하며 datasource 초기화가 다시 실행되지 않는지 확인한다.
4. LBC Ingress로 **internet-facing ALB**를 public 서브넷 2개 AZ에 생성하고 HTTPS listener/Regional ACM 인증서, 80→443 redirect, `target-type=ip`, Web 8080/health 8081을 지정한다. P7 승인 전에는 `sg-alb`의 443을 승인된 시험 출발지 CIDR로 제한하고 80도 미개방 또는 같은 범위로 제한한다.
5. 관리 runner와 승인된 시험 출발지에서 health·정적 파일·폼 로그인·역할·CSRF·DB 통합시험 및 음성 통신을 점검한다. 테스트 계정은 승인된 DB bootstrap으로 생성하며 공용 자격증명을 배포하지 않는다. 전체 도메인 브라우저 동선과 WAF 검증은 P7에서 완료한다.
6. ALB ARN/DNS/hosted zone ID를 검증·내보내 edge stack에 전달한다. App Service를 ALB가 직접 노출하는 우회 rule은 만들지 않는다.

**산출물:** Helm chart/환경 values, target health 증거, 제한된 출발지 E2E 보고서, edge 입력값.\
**완료 조건:** 2 AZ 배치와 healthy targets, Web→App→DB 성공, Web→DB 실패, readiness 실패 App의 트래픽 제외.\
**실패 대응:** Git의 이전 digest/values로 되돌리고 migration 호환성을 먼저 확인. ALB 변경은 controller reconcile과 SG/인증서 상태를 추적한다.

### Phase 7 — WAF·TLS·도메인·안전한 공개

**목표:** WAF·TLS·도메인과 애플리케이션 인증을 검증한 뒤 공개 접근을 승인한다.

**작업**
1. DB 계정·비밀번호 해시·읽기/쓰기 역할·Spring Session JDBC·CSRF·쿠키를 재검증한다. 인증 구현 전에는 무인증 상태이므로 공개 서비스로 승인하지 않는다.
2. Terraform edge로 Regional WebACL, 관리형 규칙 3종, 5분/IP 2,000 요청 rate rule, `aws_wafv2_web_acl_association`을 구성한다. 시험 출발지 제한을 유지한 채 count로 오탐을 관측하고 승인한 규칙을 block으로 전환한다.
3. WAF 로그를 CloudWatch Logs(retention 30일), ALB 액세스 로그를 S3(lifecycle 30일)에 연결한다. 요청 본문 미수집·쿠키 마스킹·샘플 수집 비활성화와 차단 로그를 확인한다.
4. 서울 리전 Regional ACM의 DNS 검증/인증서와 ALB HTTPS 443 listener를 확인하고 Route 53 A alias를 연결한다. HTTP 80은 443 redirect만 허용한다.
5. Web의 canonical Host/HTTPS·클라이언트 IP 헤더 정규화, App의 HTTPS Location·Secure 쿠키를 확인한다.
6. 브라우저에서 로그인→보호자/반려동물/방문 등록→검색→로그아웃을 시험한다. redirect·CSS·이미지·JSON/XML·쿠키·한글/쿼리 인코딩도 확인한다.
7. 미인증/권한 부족/CSRF/위조 forwarded header, 노드·DB 직접 접근, Web→DB 차단 및 SQLi/악성 입력·rate rule 차단을 정상 대조군과 함께 시험한다. 인증·WAF gate 통과 후에만 `sg-alb`의 443을 `0.0.0.0/0`로 확대하고 공개 승인한다. ALB 직접 도메인 경로는 정상 진입점이다.

**산출물:** edge IaC, WAF/라우팅/인증 계약, 브라우저 E2E, 도메인/TLS·안전한 공개 승인 보고서.\
**완료 조건:** HTTPS 도메인에서 정상 동작, WAF association·block 동작·로그 확인, 내부 주소·비밀 미노출, 미인증 업무 접근/권한 외 쓰기 차단.\
**실패 대응:** ALB SG를 시험 출발지 제한으로 복구하거나 listener 업무 전달을 차단한다. DNS 제거만으로 공개 차단을 대신하지 않으며 이전 정상 Ingress/edge 구성을 복구하고 재검증한다.

### Phase 8 — CI/CD와 릴리스·롤백 자동화

**목표:** 코드 변경을 테스트된 불변 이미지와 승인된 선언으로 연결한다.

**파이프라인**

```text
PR → Maven verify + MySQL 통합시험 + 보안/설정 검사
 → merge → 이미지 build → SBOM/취약점 검사 → ECR push + digest 기록
 → 배포 Git digest 변경 PR → 환경 승인
 → Argo CD sync: migration gate → App/Web rollout → E2E
 → 실패 시 이전 배포 Git으로 revert + 데이터 영향 판단
```

**작업**
1. 테스트용 MySQL은 격리된 CI service/Testcontainers로 사용한다. H2 테스트만으로 RDS 호환성을 대신하지 않는다.
2. 이미지에 commit/release metadata를 넣고 tag immutability와 digest 배포를 적용한다. CI AWS 권한은 필요한 ECR 등으로 제한한다.
3. Helm lint/template, YAML/schema 검사와 가능하면 server-side dry-run을 단계별 실행한다. Deployment dry-run만으로 아직 생성되지 않은 하위 Pod의 PSA·Quota·스케줄링 검증이 끝나지는 않는다. 격리된 검증 namespace에서 실제 Pod 생성·기동과 기능 회귀시험까지 통과해야 승격한다.
4. migration 도구의 schema lock 및 이전 앱 호환성을 검사한다. 여러 App initContainer에서 migration을 무제어 반복하지 않는다.
5. dev 자동 배포, 운영 승인 후 승격. GitOps가 관리하는 replica/digest를 수동 명령과 경쟁시키지 않도록 HPA replicas 필드를 조정한다.
6. 의도적 잘못된 이미지/probe를 사용해 배포 중단과 이전 digest 복구를 재현한다.

**산출물:** CI workflow, 배포 Git/Argo Application, artifact provenance, release/rollback runbook.\
**완료 조건:** 깨끗한 commit에서 같은 절차 재현, gate 실패 시 승격 중단, 이전 digest 복구 확인.\
**실패 대응:** Git revert가 정식 롤백. 긴급 `rollout undo` 사용 시 GitOps sync와 충돌을 통제하고 반드시 Git 상태도 일치시킨다. DB 변경은 별도 판단한다.

### Phase 9 — 확장·관측·비용 튜닝

**목표:** 부하 증가와 장애 징후를 측정하고 자동 대응한다.

**작업**
1. HPA 2~6, CPU 기준·stabilization·scale-down 정책을 적용하고 요청 부하에서 증가/감소를 확인한다.
2. Pending Pod 상황에서 Cluster Autoscaler가 대상 MNG를 늘리는지 검증한다. 최대 노드 수와 DB pool 예산을 함께 제한한다.
3. WAF allowed/blocked/rate 지표·로그, ALB target/4xx/5xx/latency·S3 액세스 로그, Web/App 구조화 로그, JVM/GC/pool, EKS node/pod, RDS 지표를 연결한다.
4. 시작 알람 예: 5xx >1%/5분(최소 요청수 조건), unhealthy target >0/지속, App replica 부족, DB 연결 사용률 >80%, storage 여유 <20%, 반복 OOM. 실제 기준은 baseline으로 튜닝한다.
5. 개인정보·토큰·쿼리/본문 로깅을 제한하고 로그 retention/수집량/알람 전달을 확인한다.
6. 요청을 여러 연결로 발생시켜 App 분산을 확인한다. ClusterIP 및 upstream keepalive의 연결 단위 분산을 이해하고 요청 수가 완벽하게 동일해야 한다고 요구하지 않는다.

**산출물:** 부하 보고서, HPA/노드 확장 그래프, dashboard, 알람 증거, 비용 조정표.\
**완료 조건:** 합의한 요청률/오류율/p95 충족, scale-out/in 관측, 알람의 실제 수신 확인.\
**실패 대응:** requests/limits/HPA/pool/쿼리와 병목을 함께 조정. DB가 병목인데 App replicas만 무한히 늘리지 않는다.

### Phase 10 — 장애·복구 검증·인수·종료

**목표:** 서비스와 데이터의 복구 가능성을 입증하고 재현 자료를 남긴다.

**작업**
1. Pod 삭제, DB 접속 장애, node drain, 제한된 AZ 장애 모의, rolling update, Secret rotation을 순서대로 시험한다. 한 번에 여러 장애를 주입하지 않는다.
2. RDS Multi-AZ failover 후 DNS 재해석/pool 재연결·진행 중 요청 영향·재전송 중복을 측정한다.
3. PITR/snapshot으로 **별도 DB**를 복원하고 데이터 시점/건수/업무 기능을 검증한 다음 승인된 전환 절차를 시험한다.
4. 목표 제안: 데이터 복구 RPO ≤5분, RTO ≤60분. 가정일 뿐 보장이 아니며 실제 관측값과 차이를 기록한다. Multi-AZ 고가용성과 백업 복구를 구분한다.
5. 인수 보고서에 아키텍처·버전·비용·테스트·실패/수정 이력·runbook·화면/로그 증빙을 모은다.
6. 실습 종료 시 백업/증빙 보관 승인 후 유료 자원을 의존성 역순으로 제거하고 잔존 과금을 확인한다.

**산출물:** 장애/복구 보고서, 최종 인수 체크리스트, 운영 runbook, 비용·정리 증거.\
**완료 조건:** 아래 인수 테스트 충족, 미충족은 영향/소유자/해결 일정을 명시. 실행하지 않은 항목을 성공으로 표시하지 않는다.\
**실패 대응:** 장애 주입 중단→이전 정상 구성→데이터 일관성 확인. 복원/삭제는 승인 없이 원본 DB에 덮어쓰지 않는다.

## 9. 최종 인수 테스트

| ID | 시험 | 통과 기준 | 증빙 |
|---|---|---|---|
| T01 | 빌드/런타임 | pinned SHA, Maven 테스트, Tomcat WAR/JSP 정상 | CI log, image digest |
| T02 | UI end-to-end | **HTTPS 도메인(ALB)에서** 로그인·검색·등록·수정·방문·로그아웃 | 브라우저 기록, DB 확인 |
| T03 | HTTP 계약 | root/static/JSON/XML/폼/3xx/쿼리/쿠키 보존 | 응답 헤더·자산·네트워크 기록 |
| T04 | 경계 차단 | 노드·DB 직접 접근 실패, Web→DB 실패, WAF 차단 규칙 동작(SQLi/악성 입력) 확인 | SG/NetworkPolicy 음성 테스트, WAF block 로그·정상 대조군 |
| T05 | 인증·인가·CSRF | 미인증 차단, ROLE_READER 쓰기 금지/ROLE_WRITER 허용, 권한 부족 403, CSRF 누락·변조 거부 | 민감값 제거 테스트 로그 |
| T06 | 초기화/영속성 | App 재생성·동시 기동 후 데이터 유지, DDL 재실행 없음 | migration history, 레코드 비교 |
| T07 | 세션/배포 | Pod 교체·분산 후 로그인 유지, 이전 버전 복구 가능 | 요청 추적, release 기록 |
| T08 | 프로브 | DB 장애 시 App ready 실패/live 유지, 복구 후 정상 | kube events, probe 응답 |
| T09 | 부하 | 합의 요청률·p95·성공률 충족, HPA와 노드 증가 관측 | 부하 결과/대시보드 |
| T10 | 드레인/가용성 | drain/rollout 중 허용 오류 예산 이내 | 연속 요청/종료 시간 기록 |
| T11 | RDS 장애/복구 | failover 재연결과 PITR 실제 복원, RPO/RTO 기록 | DB 이벤트/복원 검증 |
| T12 | Secret/로그 | 이미지·state·로그 비밀 없음, rotation 후 재접속 | 스캔/rotation/마스킹 증빙 |
| T13 | 알람/비용 | 장애 알림 수신, 예산/잔존 과금 확인 | 알림·비용 보고서 |
| T14 | 재현성 | 새 dev 환경에서 IaC/Helm/CI 절차 재현 | apply/sync/검증 결과 |

## 10. 비용·운영 runbook·확장 과제

### 10.1 비용 모델

정확한 견적은 Phase 0에서 AWS Pricing Calculator의 서울 리전 단가·계정 조건으로 산정한다. PDF/노션의 Docker 단일 EC2 실습 비용은 EKS 프로젝트 견적이 아니다.

| 비용 요소 | 축소 실습안 | 운영 기준안 |
|---|---|---|
| EKS control plane | 1 cluster, 생성 기간 내 계속 과금 | 환경별 cluster 분리 검토, 지원 기간 관리 |
| Worker | 공유 2노드로 축소 가능, Tier SG 격리 약화 명시 | Web/system 2 + App 2부터 시작, 확장 여유 |
| NAT | Regional NAT Gateway 1개(AZ 자동 프로비저닝, EIP는 AZ별 명시), 기간·처리량 축소 | Regional NAT 1개 + AZ 수만큼 EIP + 처리 GB |
| ALB | 1개, 시간 + LCU | ALB 시간 + LCU·전송량 |
| AWS WAF | WebACL 월정액 + 규칙 요금 + 요청 100만 건당 과금 | 동일 과금 요소 + 규모별 요청량·로그; 정확한 단가는 Phase 0에서 Pricing Calculator로 확인 |
| RDS | Single-AZ 허용, HA 시험은 별도 | Multi-AZ + backup/storage/I/O |
| 기타 | ECR, EBS, public IPv4, endpoint ENI, 로그, Secrets, KMS, 도메인 | 같은 항목 + 규모별 사용량 |

월 비용은 `EKS 시간 + EC2 시간 + EBS + RDS + ALB 시간/LCU + WAF WebACL·규칙 월정액/요청 + NAT 시간/GB + endpoint 시간/GB + 로그/전송/백업/보안 서비스`로 계산한다. NAT와 interface endpoint를 무조건 모두 만드는 것이 더 저렴하지는 않다. 실제 요청량·트래픽 목적지·AZ 간 전송을 기준으로 선택한다.

예산 알림은 합의 금액의 50/80/100%로 설정한다. 알림은 자동 비용 상한이 아니다. EKS는 EC2처럼 클러스터를 중지해 control plane 과금을 멈추는 방식이 아니며, 노드 0대만으로 전체 비용이 사라지지 않는다.

### 10.2 장애 진단 순서

1. Route 53/ACM/ALB listener·WAF 차단 여부 → 4xx/5xx와 요청 추적 정보 확인.
2. ALB target health/SG, Web 로그 확인.
3. Web→App DNS/Service/EndpointSlice/readiness/NetworkPolicy 확인.
4. App 예외/JVM/connection pool/설정·Secret 파일 확인.
5. RDS SG/TLS/연결 수/느린 쿼리/failover 이벤트 확인.

| 증상 | 우선 확인 |
|---|---|
| 403 또는 정상 폼 차단 | WAF terminating rule/count·block 로그, Spring Security 역할/CSRF, 정상 대조군 |
| ALB 404 또는 정적 파일 깨짐 | Host/path rule, Web proxy 경로, WAR root context, asset path |
| 502/503 | healthy targets, probe, SG, Nginx upstream, App boot |
| 504 | ALB idle timeout, Web upstream timeout, DB/pool/쿼리 timeout, SG |
| 로그인 redirect loop·HTTP Location | canonical scheme/host, 폼 로그인 설정, 세션/쿠키 |
| Pod마다 로그인 상태 다름 | Spring Session 연결·테이블·직렬화, 쿠키 범위 |
| ImagePullBackOff | ECR IAM, DNS/endpoint/NAT, digest/CPU architecture |
| OOMKilled/Pending | JVM native 여유, requests/limits, AZ/taint/capacity/IP |
| 재배포 후 DB 오류/데이터 변경 | startup initializer 재활성화, migration/권한/호환성 |

### 10.3 실습 자원 정리 순서

증빙·데이터 보관 승인 및 공개 중단(ALB SG 제한) → Argo 자동 sync 중단/정리 대상 확정 → **WAF association/WebACL 제거**(Terraform edge) → **Ingress 삭제 및 LBC의 ALB/TG 삭제 완료 확인** → Route 53 alias·전용 ACM/edge 잔여 리소스 정리 → App/addon/nodegroup/cluster 정리 → 승인된 RDS 최종 snapshot 및 DB 삭제 → NAT/endpoint/ENI/SG/VPC 정리(regional NAT가 AZ에 자동 프로비저닝한 NAT와 미사용 EIP 해제까지 확인) → 필요 없는 ECR/EBS/로그/Secret 점검.

컨트롤러를 먼저 없애 ALB 삭제 finalizer가 고립되지 않도록 한다. retained snapshot·로그·도메인·state·ECR은 별도 과금될 수 있으므로 보관 기한과 소유자를 남긴다. 공유 VPC·공유 IAM·공유 DNS는 프로젝트 전용 자원과 구분한다.

### 10.4 후속 선택 과제

- **OIDC/외부 IdP:** 폼 로그인·DB 계정의 기본안을 유지하며 외부 조직 계정 연동이 필요할 때 별도 ADR로 선택한다. callback/logout URI, 역할 매핑, egress, 세션·CSRF 영향을 검증한다.
- **REST API 확장:** `/api/v1/**` CRUD와 OpenAPI를 새로 구현한 뒤 App의 token 검증/인가를 설계한다. 기존 `/vets.json` 하나로 전체 REST 전환을 완료했다고 주장하지 않는다.
- **CDN/프런트 분리:** 정적 자산만 CloudFront/S3로 옮길지, SPA를 새로 만들지 별도 ADR로 결정한다. 요청·전송 비용·cache·CORS·인증 영향을 검토한다.
- **카나리:** 기본 rolling release 안정화 이후 Argo Rollouts/지원 라우팅 계층으로 추가한다. Web ALB 가중치만 바꿔도 공통 `app-svc` 뒤 App 버전 비율이 자동 제어되지는 않는다. 버전별 Web/App 경로 또는 App 라우팅 계층까지 설계한다.
- **강화 운영:** WAF 규칙 튜닝·추가 규칙, Security Groups for Pods, Redis 세션/캐시, RDS Proxy, 다중 계정·재해복구는 측정된 필요에 따라 추가한다. 기본 WebACL·관리형 규칙은 최초 공개 범위에 포함한다.

---

**완료의 의미:** 인터넷에서 화면이 한 번 보이는 것이 아니라, 승인된 진입점과 권한으로 정상 동작하고, 이미지·배포가 재현되며, Pod 교체에도 데이터·세션이 유지되고, 장애와 복구·정리까지 증거로 설명할 수 있는 상태다.
