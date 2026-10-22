// Petclinic 3-Tier on EKS — 실제 구축 결과 토폴로지
// 생성: drawio-ai-kit (aws/build_vpc_eks.mjs 구조 기반, 좌표 하드코딩 없음)
// 실행: cd <drawio-ai-kit 설치 디렉터리> && ./node_modules/.bin/drawio-ai run <이 파일>
import { writeFileSync } from "node:fs";
import { Diagram, group, icon, renderTree } from "drawio-ai-kit";

const OUT = new URL("../docs/아키텍처_토폴로지.drawio", import.meta.url).pathname;

const d = new Diagram("network");

// ── 1. 외부 진입 (VPC 밖) ────────────────────────────────────────────────────
const external = group("external", "group_aws_cloud", "External / Edge (VPC 밖)", { dir: "row", gap: 26, align: "center" }, [
  icon("internet", "internet", "사용자 브라우저\nHTTPS 443"),
  icon("route53", "route_53", "Route 53\nclinic.mission-critical.site\n(pending)"),
  icon("acm", "certificate_manager", "ACM\nPENDING_VALIDATION\n(pending)"),
  icon("apigw", "api_gateway", "API Gateway HTTP API\npetclinic-dev-http-api\n$default · 50rps/100burst"),
]);

// ── 2. AZ 하나 = 4개 서브넷 계층 ─────────────────────────────────────────────
const az = (s, cidrs) =>
  group(`az_${s}`, "group_availability_zone", `Availability Zone ap-northeast-2${s}`, { dir: "col", gap: 26, align: "center" }, [
    group(`az_${s}_pub`, "group_subnet", `Public  ${cidrs.pub}`, { dir: "row", gap: 14 }, [
      icon(`nat_${s}`, "nat_gateway", "NAT Gateway"),
    ]),
    group(`az_${s}_ing`, "group_subnet", `Private ingress  ${cidrs.ing}`, { dir: "row", gap: 14 }, [
      icon(`vpclink_${s}`, "gateway", "VPC Link ENI"),
      icon(`alb_${s}`, "application_load_balancer", "ALB node"),
    ]),
    group(`az_${s}_wl`, "group_subnet", `Private workloads  ${cidrs.wl}`, { dir: "col", gap: 14 }, [
      icon(`web_${s}`, "ec2", "Web Pod (nginx 1.29)\n:8080 업무 / :8081 health"),
      icon(`app_${s}`, "ec2", "App Pod (Tomcat 11)\nJDK21 · :8080"),
    ]),
    group(`az_${s}_data`, "group_subnet", `Isolated data  ${cidrs.data}  (NAT 경로 없음)`, { dir: "row", gap: 14 }, [
      s === "a"
        ? icon(`rds_${s}`, "rds", "RDS standby\n(Multi-AZ 대기)")
        : icon(`rds_${s}`, "rds", "RDS MySQL 8.4.6\npetclinic-dev-mysql\ndb.m6g.large · :3306"),
    ]),
  ]);

const vpc = group("vpc", "group_vpc", "VPC 10.20.0.0/16", { dir: "col", gap: 30, align: "center" }, [
  icon("igw", "internet_gateway", "Internet Gateway"),
  group("az_row", "group_aws_cloud", "", { dir: "row", gap: 70, align: "top" }, [
    az("a", { pub: "10.20.0.0/24", ing: "10.20.8.0/24", wl: "10.20.32.0/20", data: "10.20.80.0/24" }),
    az("b", { pub: "10.20.1.0/24", ing: "10.20.9.0/24", wl: "10.20.48.0/20", data: "10.20.81.0/24" }),
  ]),
]);

// ── 3. 공유 서비스 (계정 내, VPC 밖) ────────────────────────────────────────
const shared = group("shared", "group_aws_cloud", "Shared Services (VPC 밖)", { dir: "row", gap: 22, align: "center" }, [
  icon("ecr", "ecr", "ECR\npetclinic-app · petclinic-web\nIMMUTABLE"),
  icon("secrets", "secrets_manager", "Secrets Manager\napp/db · migration/db\napp/session · app/cognito"),
  icon("cognito", "cognito", "Cognito\npetclinic-dev-users\n앱 인증 미구현 (planned)"),
  icon("kms", "key_management_service", "KMS\nalias/petclinic-dev-main"),
  icon("logs", "cloudwatch_2", "CloudWatch Logs\ncontrol plane · API access"),
  icon("ssm", "systems_manager", "Systems Manager\n관리 EC2 (SSH 없음)"),
  icon("iam", "identity_and_access_management", "IAM / IRSA ×5\nlbc · ebs-csi · CA · app · migration"),
]);

// ── 4. 트리 ─────────────────────────────────────────────────────────────────
const tree = group("region", "group_region", "Region ap-northeast-2 · Account 123456789012", { dir: "col", gap: 30, align: "center" }, [
  external,
  vpc,
  shared,
]);

renderTree(d, tree, [40, 80]);

d.title("Petclinic 3-Tier on EKS — API Gateway · VPC Link V2 · internal ALB · RDS MySQL (ap-northeast-2)");

// ── 5. EKS / ALB 프레임 (여러 AZ 에 걸친 단일 리소스) ───────────────────────
d.clusterBox("eks_cluster", ["az_a_wl", "az_b_wl"], "Amazon EKS 1.34 · petclinic-dev (private endpoint) · MNG web-system ×2 + app ×2", {
  icon: "eks",
});
d.clusterBox("alb_box", ["az_a_ing", "az_b_ing"], "internal ALB k8s-petclinic-74aca36a20 · VPC Link V2 petclinic-dev-vpclink · target-type=ip", {
  icon: "application_load_balancer",
});

// ── 6. 요청 경로 1→6 (실선 + 번호 배지) ─────────────────────────────────────
d.link("internet", "apigw", "HTTPS 443", { dir: "LR", badge: 1 });
d.link("apigw", "vpclink_b", "HTTP_PROXY / VPC_LINK", { dir: "TB", badge: 2 });
d.link("vpclink_b", "alb_b", "", { dir: "LR", badge: 3 });
d.link("alb_b", "web_b", ":8080", { dir: "TB", badge: 4 });
d.link("web_b", "app_b", "app-svc:8080", { dir: "TB", badge: 5 });
d.link("app_b", "rds_b", "JDBC 3306 (TLS)", { dir: "TB", badge: 6 });

// 같은 경로의 AZ-A 쪽 (배지 없이 병렬 경로)
d.link("apigw", "vpclink_a", "", { dir: "TB", role: "fanout" });
d.link("vpclink_a", "alb_a", "", { dir: "LR" });
d.link("alb_a", "web_a", "", { dir: "TB" });
d.link("web_a", "app_a", "", { dir: "TB" });

// ── 7. 보조 / 미구현 경로 (점선) ────────────────────────────────────────────
d.link("nat_a", "igw", "egress", { dir: "TB", dash: true });
d.link("nat_b", "igw", "", { dir: "TB", dash: true });
d.link("ecr", "az_b_wl", "image pull", { dir: "TB", dash: true });
d.link("secrets", "az_b_wl", "secret file mount", { dir: "TB", dash: true });
d.link("cognito", "az_a_wl", "OIDC (planned)", { dir: "TB", dash: true });
d.link("logs", "az_a_wl", "logs / metrics", { dir: "TB", dash: true });
d.link("route53", "apigw", "custom domain (pending)", { dir: "TB", dash: true });
d.link("acm", "alb_a", "HTTPS 443 (pending)", { dir: "TB", dash: true });

// ── 8. 범례 ─────────────────────────────────────────────────────────────────
const vpcRect = d.rect("vpc");
const legendY = vpcRect.y + vpcRect.h + 120;
d.box(
  "legend",
  [40, legendY],
  [760, 104],
  [
    "범례",
    "──  실선 : 실제 동작 경로 (번호 1→6 = 사용자 → API Gateway → VPC Link → ALB → Web → App → RDS)",
    "- - 점선 : 보조 경로 및 미구현 항목   ·  ACM = PENDING_VALIDATION, Cognito 앱 인증 = planned",
    "Isolated data 서브넷 : 라우팅에 NAT/I GW 경로가 없음 (VPC local 만) · RDS Multi-AZ (2b primary / 2a standby)",
  ].join("\n"),
  { fill: "#FFFFFF", stroke: "#999999", va: "top" }
);

const res = d.validate();
console.log("VALIDATE:", JSON.stringify({ ok: res.ok, errors: res.errors, warnings: res.warnings, advice: res.audit.advice }));
writeFileSync(OUT, d.mxfile("Petclinic 3-Tier on EKS — topology"));
console.log("WROTE:", OUT);
