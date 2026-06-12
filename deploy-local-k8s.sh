#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

IMAGE_NAME="wedding-web-local"
IMAGE_TAG="latest"
WITH_INGRESS="true"
WITH_TLS="true"
NAMESPACE="wedding"
DEPLOYMENT_NAME="wedding-web"
KUBECTL_CMD=("kubectl")

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build Docker image, load it into local Kubernetes (kind/k3d/minikube/microk8s), and deploy manifests.

Options:
  --image <name>         Docker image name (default: ${IMAGE_NAME})
  --tag <tag>            Docker image tag (default: ${IMAGE_TAG})
  --with-ingress         Also deploy ingress resource
  --with-tls             Also deploy cert-manager ClusterIssuer + ingress TLS config
                         (implies --with-ingress)
  -h, --help             Show this help

Examples:
  ./deploy-local-k8s.sh
  ./deploy-local-k8s.sh --with-ingress --with-tls
  ./deploy-local-k8s.sh --with-tls --image wedding-web-local --tag v2
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

setup_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    KUBECTL_CMD=("kubectl")
    return 0
  fi

  if command -v microk8s >/dev/null 2>&1; then
    KUBECTL_CMD=("microk8s" "kubectl")
    return 0
  fi

  echo "Missing required command: kubectl (or microk8s kubectl)" >&2
  exit 1
}

kctl() {
  "${KUBECTL_CMD[@]}" "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image)
        IMAGE_NAME="${2:-}"
        shift 2
        ;;
      --tag)
        IMAGE_TAG="${2:-}"
        shift 2
        ;;
      --with-ingress)
        WITH_INGRESS="true"
        shift
        ;;
      --with-tls)
        WITH_TLS="true"
        WITH_INGRESS="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "${IMAGE_NAME}" || -z "${IMAGE_TAG}" ]]; then
    echo "Image name and tag must not be empty." >&2
    exit 1
  fi
}

current_context() {
  kctl config current-context 2>/dev/null || true
}

load_image_to_local_cluster() {
  local image_ref="$1"
  local ctx
  ctx="$(current_context)"

  if [[ -z "${ctx}" ]]; then
    echo "Could not detect current kubectl context. Skipping local image load."
    return 0
  fi

  if [[ "${ctx}" == kind-* ]]; then
    local kind_cluster="${ctx#kind-}"
    echo "Loading image into kind cluster: ${kind_cluster}"
    kind load docker-image "${image_ref}" --name "${kind_cluster}"
    return 0
  fi

  if [[ "${ctx}" == k3d-* ]]; then
    local k3d_cluster="${ctx#k3d-}"
    echo "Importing image into k3d cluster: ${k3d_cluster}"
    k3d image import "${image_ref}" -c "${k3d_cluster}"
    return 0
  fi

  if [[ "${ctx}" == "minikube" ]]; then
    echo "Loading image into minikube"
    minikube image load "${image_ref}"
    return 0
  fi

  if [[ "${ctx}" == microk8s* ]]; then
    require_cmd microk8s
    echo "Importing image into microk8s containerd"
    if docker save "${image_ref}" | microk8s ctr images import - >/dev/null 2>&1; then
      return 0
    fi

    docker save "${image_ref}" | microk8s ctr -n k8s.io images import -
    return 0
  fi

  echo "Context '${ctx}' is not kind/k3d/minikube/microk8s."
  echo "Assuming cluster can pull image '${image_ref}' directly."
}

main() {
  parse_args "$@"

  require_cmd docker
  setup_kubectl

  if [[ "${WITH_TLS}" == "true" ]]; then
    echo "TLS mode enabled: expecting cert-manager and ingress-nginx in cluster."
  fi

  local image_ref="${IMAGE_NAME}:${IMAGE_TAG}"

  echo "Building image: ${image_ref}"
  docker build -t "${image_ref}" "${SCRIPT_DIR}"

  local ctx
  ctx="$(current_context)"
  echo "Using kubectl context: ${ctx:-unknown}"

  if [[ "${ctx}" == kind-* ]]; then
    require_cmd kind
  elif [[ "${ctx}" == k3d-* ]]; then
    require_cmd k3d
  elif [[ "${ctx}" == "minikube" ]]; then
    require_cmd minikube
  elif [[ "${ctx}" == microk8s* ]]; then
    require_cmd microk8s
  fi

  load_image_to_local_cluster "${image_ref}"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap "rm -rf -- '${tmp_dir}'" EXIT

  cp "${K8S_DIR}/namespace.yaml" "${tmp_dir}/namespace.yaml"
  cp "${K8S_DIR}/deployment.yaml" "${tmp_dir}/deployment.yaml"
  cp "${K8S_DIR}/service.yaml" "${tmp_dir}/service.yaml"

  if [[ "${WITH_INGRESS}" == "true" ]]; then
    cp "${K8S_DIR}/ingress.yaml" "${tmp_dir}/ingress.yaml"
  fi

  if [[ "${WITH_TLS}" == "true" ]]; then
    cp "${K8S_DIR}/cluster-issuer-letsencrypt.yaml" "${tmp_dir}/cluster-issuer-letsencrypt.yaml"
  fi

  cat > "${tmp_dir}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
EOF

  if [[ "${WITH_INGRESS}" == "true" ]]; then
    cat >> "${tmp_dir}/kustomization.yaml" <<EOF
  - ingress.yaml
EOF
  fi

  if [[ "${WITH_TLS}" == "true" ]]; then
    cat >> "${tmp_dir}/kustomization.yaml" <<EOF
  - cluster-issuer-letsencrypt.yaml
EOF
  fi

  cat >> "${tmp_dir}/kustomization.yaml" <<EOF
images:
  - name: ghcr.io/jkralik/wedding
    newName: ${IMAGE_NAME}
    newTag: ${IMAGE_TAG}
EOF

  echo "Applying manifests"
  kctl apply -k "${tmp_dir}"

  echo "Waiting for rollout"
  kctl -n "${NAMESPACE}" rollout status deployment/"${DEPLOYMENT_NAME}" --timeout=120s

  echo "Deployment finished."
  kctl -n "${NAMESPACE}" get pods -o wide
  kctl -n "${NAMESPACE}" get svc

  if [[ "${WITH_INGRESS}" == "true" ]]; then
    kctl -n "${NAMESPACE}" get ingress
  fi
}

main "$@"
