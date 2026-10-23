// Petclinic 3-Tier on EKS — 실제 구축 결과 토폴로지 (v2)
//   v2: internet-facing ALB + AWS WAF 단일 진입점. API Gateway / VPC Link / Cognito 제거.
//
//   v3 개선 (EKS 묘사 보강):
//     1) EKS Control Plane 밴드 신설 (API/etcd/컨트롤러/OIDC + 관리형 addon)
//     2) workloads 서브넷 안에 "노드(EC2) 프레임"을 두고 그 안에 Pod 를 배치
//        → Pod 를 EC2 아이콘으로 그리던 오류 수정 (Pod = container, 노드 = ec2)
//     3) Pod IP ↔ 노드 IP 를 함께 표기 (VPC CNI: Pod IP = 노드 ENI 보조 IP)
//     4) "우리가 선언한 것 → 컨트롤러가 만든 것" 매핑 박스 추가
//
// 생성: drawio-ai-kit (aws/build_vpc_eks.mjs 구조 기반, 좌표 하드코딩 없음)
// 실행: cd <drawio-ai-kit 설치 디렉터리> && ./node_modules/.bin/drawio-ai run <이 파일>
import { writeFileSync } from "node:fs";
import { Diagram, group, icon, renderTree } from "drawio-ai-kit";

const OUT = "/home/grapefruit/kubenetes/EKS_Project/아키텍처_토폴로지.drawio";

const d = new Diagram("network");

// ── 0. EKS Control Plane (AWS 관리형 · 우리 VPC 밖) ─────────────────────────
const controlPlane = group("eks_cp", "group_aws_cloud", "Amazon EKS Control Plane — AWS 관리형 (우리 계정 VPC 밖)", { dir: "row", gap: 24, align: "center" }, [
  icon("cp_api", "eks_cloud", "API Server\nprivate endpoint 전용\n(우리는 SSM 포트포워딩으로 접근)"),
  icon("cp_etcd", "key_management_service", "etcd\nsecrets → KMS 암호화"),
  icon("cp_ctrl", "cluster", "scheduler · controller-manager\nOIDC provider (IRSA 신뢰)"),
  icon("cp_addon", "container_1", "관리형 addon\nvpc-cni · kube-proxy · coredns\neks-pod-identity-agent · ebs-csi"),
]);

// ── 1. 외부 진입 (VPC 밖) ────────────────────────────────────────────────────
//    internet → WAF 가 실제 요청 경로, Route 53 / ACM 은 지원 리소스.
const external = group("external", "group_aws_cloud", "External / Edge (VPC 밖)", { dir: "row", gap: 26, align: "center" }, [
  icon("route53", "route_53", "Route 53\nclinic.mission-critical.site\nA alias → ALB"),
  icon("internet", "internet", "사용자 브라우저\nHTTPS 443"),
  icon("waf", "waf", "AWS WAF (Regional)\npetclinic-dev-alb-waf\nCommon · SQLi · KnownBadInputs\nIP rate 2,000 / 5분"),
  icon("acm", "certificate_manager", "ACM\nISSUED\nclinic.mission-critical.site"),
]);

// ── 2. AZ 하나 = 3개 서브넷 계층 ─────────────────────────────────────────────
//    workloads 서브넷 안에 "노드(EC2)" 프레임을 두고, 그 안에 Pod 를 넣는다.
//    노드 = EC2 인스턴스(ec2 아이콘) / Pod = 컨테이너 묶음(container 아이콘).
const az = (s, c) => {
  const nodeFrame = (role, nodeIp, tier, podId, podLabel) =>
    group(`node_${s}_${role}`, "group_ec2_instance_contents",
      `노드 ${nodeIp} · EC2 ${c.instanceType} · tier=${tier} · kubelet`, { dir: "row", gap: 12, align: "center" }, [
        icon(podId, "container_1", podLabel),
      ]);

  return group(`az_${s}`, "group_availability_zone", `Availability Zone ap-northeast-2${s}`, { dir: "col", gap: 26, align: "center" }, [
    group(`az_${s}_pub`, "group_subnet", `Public  ${c.pub}`, { dir: "row", gap: 14 }, [
      icon(`alb_${s}`, "application_load_balancer", "ALB node\n(internet-facing)"),
      icon(`nat_${s}`, "nat_gateway", "NAT Gateway"),
    ]),
    group(`az_${s}_wl`, "group_subnet", `Private workloads  ${c.wl}  (노드 IP 와 Pod IP 가 같은 대역)`, { dir: "col", gap: 14 }, [
      nodeFrame("web", c.webNode, "web-system", `web_${s}`, `Pod web (nginx 1.29)\n${c.webPod}:8080\n↳ 노드 ENI 보조 IP`),
      nodeFrame("app", c.appNode, "app", `app_${s}`, `Pod app (Tomcat 11)\n${c.appPod}:8080\n↳ 노드 ENI 보조 IP`),
    ]),
    group(`az_${s}_data`, "group_subnet", `Isolated data  ${c.data}  (NAT 경로 없음)`, { dir: "row", gap: 14 }, [
      s === "a"
        ? icon(`rds_${s}`, "rds", "RDS standby\n(Multi-AZ 대기)")
        : icon(`rds_${s}`, "rds", "RDS MySQL 8.4.6\npetclinic-dev-mysql\ndb.m6g.large · :3306"),
    ]),
  ]);
};

const vpc = group("vpc", "group_vpc", "VPC 10.20.0.0/16", { dir: "col", gap: 30, align: "center" }, [
  icon("igw", "internet_gateway", "Internet Gateway"),
  group("az_row", "group_aws_cloud", "", { dir: "row", gap: 70, align: "top" }, [
    az("a", {
      pub: "10.20.0.0/24", wl: "10.20.32.0/20", data: "10.20.80.0/24", instanceType: "m6i.large",
      webNode: "10.20.42.100", webPod: "10.20.35.83", appNode: "10.20.46.238", appPod: "10.20.47.46",
    }),
    az("b", {
      pub: "10.20.1.0/24", wl: "10.20.48.0/20", data: "10.20.81.0/24", instanceType: "m6i.large",
      webNode: "10.20.54.237", webPod: "10.20.57.220", appNode: "10.20.53.165", appPod: "10.20.58.76",
    }),
  ]),
]);

// ── 3. 공유 서비스 (계정 내, VPC 밖) ────────────────────────────────────────
const shared = group("shared", "group_aws_cloud", "Shared Services (VPC 밖)", { dir: "row", gap: 22, align: "center" }, [
  icon("ecr", "ecr", "ECR\npetclinic-app · petclinic-web\nIMMUTABLE"),
  icon("secrets", "secrets_manager", "Secrets Manager\napp/db · migration/db\napp/session (RDS 관리형)"),
  icon("kms", "key_management_service", "KMS\nalias/petclinic-dev-main"),
  icon("logs", "cloudwatch_2", "CloudWatch Logs\ncontrol plane · WAF 로그\naws-waf-logs-petclinic-dev"),
  icon("ssm", "systems_manager", "Systems Manager\n관리 EC2 (SSH 없음)"),
  icon("iam", "identity_and_access_management", "IAM / IRSA ×5\nlbc · ebs-csi · CA · app · migration"),
]);

// ── 4. 트리 ─────────────────────────────────────────────────────────────────
//    Control Plane 을 최상단에 둔다(우리 VPC 밖). 요청 경로(WAF→ALB)는
//    external 과 VPC 가 인접해야 선이 다른 밴드를 가로지르지 않는다.
const tree = group("region", "group_region", "Region ap-northeast-2 · Account 123456789012", { dir: "col", gap: 30, align: "center" }, [
  controlPlane,
  external,
  vpc,
  shared,
]);

renderTree(d, tree, [40, 80]);

d.title("Petclinic 3-Tier on EKS — internet-facing ALB · AWS WAF · RDS MySQL (ap-northeast-2)");

// ── 5. 클러스터 / ALB 프레임 (여러 AZ 에 걸친 단일 리소스) ───────────────────
d.clusterBox("eks_cluster", ["az_a_wl", "az_b_wl"],
  "Amazon EKS 1.34 · petclinic-dev — 이 두 서브넷의 노드 4대가 클러스터에 등록됨 (MNG web-system ×2 + app ×2, taint 없음 → nodeSelector 로 분리)",
  { icon: "eks" });
d.clusterBox("alb_box", ["az_a_pub", "az_b_pub"],
  "internet-facing ALB k8s-petclinic-de153205fb · target-type=ip · Target Group 에 Pod IP 를 등록 · AWS WAF 연결",
  { icon: "application_load_balancer" });

// ── 6. 요청 경로 1→5 (실선 + 번호 배지) ─────────────────────────────────────
d.link("internet", "waf", "HTTPS 443", { dir: "LR", badge: 1 });
d.link("waf", "alb_b", "허용된 요청만 전달", { dir: "TB", badge: 2 });
d.link("alb_b", "web_b", ":8080 (HTTP)", { dir: "TB", badge: 3 });
d.link("web_b", "app_b", "app-svc:8080", { dir: "TB", badge: 4 });
d.link("app_b", "rds_b", "JDBC 3306 (TLS)", { dir: "TB", badge: 5 });

// 같은 경로의 AZ-A 쪽 (배지 없이 병렬 경로)
d.link("waf", "alb_a", "", { dir: "TB", role: "fanout" });
d.link("alb_a", "web_a", "", { dir: "TB" });
d.link("web_a", "app_a", "", { dir: "TB" });

// ── 7. 지원 / 보조 경로 (점선) ──────────────────────────────────────────────
d.link("route53", "alb_a", "A alias (DNS)", { dir: "TB", dash: true });
d.link("acm", "alb_b", "TLS 인증서", { dir: "TB", dash: true });
d.link("nat_a", "igw", "egress", { dir: "TB", dash: true });
d.link("nat_b", "igw", "", { dir: "TB", dash: true });
d.link("ecr", "az_b_wl", "image pull", { dir: "TB", dash: true });
d.link("secrets", "az_b_wl", "secret file mount", { dir: "TB", dash: true });
d.link("logs", "az_a_wl", "logs / metrics", { dir: "TB", dash: true });
// kubelet → API Server 상태 보고는 Control Plane 밴드 라벨로만 표기한다.
//   (선을 그으면 external 밴드를 가로지른다)

// ── 8. 선언 → 생성 매핑 ─────────────────────────────────────────────────────
const regionRect = d.rect("region");
const declY = regionRect.y + regionRect.h + 40;
d.box(
  "declared",
  [40, declY],
  [1358, 148],
  [
    "우리가 선언한 것 (k8s/*.yaml)   →   컨트롤러가 만든 것",
    "Deployment web (replicas 2)    →   ReplicaSet  →  Pod web ×2          ｜  Deployment app (replicas 2)  →  ReplicaSet  →  Pod app ×2",
    "Service web-svc (ClusterIP)    →   Endpoints = Pod IP ×2 (:8080)      ｜  Service app-svc (ClusterIP)  →  Endpoints = Pod IP ×2",
    "Ingress petclinic-web          →   AWS Load Balancer Controller  →  ALB + Target Group + TargetGroupBinding (target-type=ip)",
    "Secret app-config              →   /etc/petclinic/data-access.properties 파일 마운트 (readOnly 0440)",
    "ServiceAccount petclinic-app + IRSA role-arn   →   Pod 안에 AWS 자격증명 주입 (노드 권한이 아님)",
  ].join("\n"),
  { fill: "#F5F5F5", stroke: "#999999", va: "top" }
);

// ── 9. 범례 ─────────────────────────────────────────────────────────────────
const legendY = declY + 148 + 30;
d.box(
  "legend",
  [40, legendY],
  [1358, 104],
  [
    "범례",
    "──  실선 : 실제 동작 경로 (번호 1→5 = 브라우저 → AWS WAF → internet-facing ALB → Pod web → Pod app → RDS)",
    "- - 점선 : 지원 경로 (DNS / TLS / egress / image pull / secret mount / logs / kubelet 상태 보고)",
    "Pod IP = 노드 ENI 의 보조 IP (VPC CNI) → ALB 가 Pod 를 직접 target 으로 등록한다. ClusterIP 는 VPC 대역 밖의 가상 IP (iptables).",
    "Isolated data 서브넷 : NAT/IGW 경로 없음 (VPC local 만) · RDS Multi-AZ (2b primary / 2a standby)",
  ].join("\n"),
  { fill: "#FFFFFF", stroke: "#999999", va: "top" }
);

const res = d.validate();
console.log("VALIDATE:", JSON.stringify({ ok: res.ok, errors: res.errors, warnings: res.warnings, advice: res.audit.advice }));
writeFileSync(OUT, d.mxfile("Petclinic 3-Tier on EKS — topology (v2)"));
console.log("WROTE:", OUT);
