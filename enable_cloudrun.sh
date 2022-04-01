#!/bin/bash
 
# Enable Cloud Run for Anthos by:
#  1) registring a GKE cluster to Anthos Fleets
#  2) installing Anthos Service Mesh 1.12 in-cluster control plane
#  3) deploying Istio IngressGateway in private/public mode
#  4) Enabling Cloud Run for Anthos in private/public mode
#
# This script expects the following tools to be installed
#  - gcloud
#  - kubectl
#
# Additionally kubectl access to the GKE cluster from the machine is required

usage() { echo "Usage: $0 -p GCP_PROJECT_ID -c CLUSTER_NAME -l REGION_OR_ZONE -s private|public" 1>&2; exit 1; }

while getopts s:p:c:l: opt
do
   case $opt in
       s) SCOPE=$OPTARG;;
       p) PROJECT_ID=$OPTARG;;
       c) CLUSTER_NAME=$OPTARG;;
       l) CLUSTER_LOCATION=$OPTARG;;
       *)
        usage
        ;;
   esac
done

shift $((OPTIND-1))

if [ -z "${SCOPE}" ] || [ -z "${PROJECT_ID}" ] || [ -z "${CLUSTER_NAME}" ] || [ -z "${CLUSTER_LOCATION}" ]; then
    usage
fi

set -eu

enable_fleet() {
  echo "Enabling Fleet for $PROJECT_ID - $CLUSTER_NAME"
  gcloud container hub memberships register "${CLUSTER_NAME}" --project="$PROJECT_ID" --gke-cluster="${CLUSTER_LOCATION}/${CLUSTER_NAME}" --enable-workload-identity
  echo
}

install_anthos() {
  echo "Installing Anthos Service Mesh for $PROJECT_ID - $CLUSTER_NAME"
  if [ ! -f /tmp/asmcli ]; then
    # install ASM
    curl https://storage.googleapis.com/csm-artifacts/asm/asmcli_1.12 > /tmp/asmcli
    chmod +x /tmp/asmcli
  fi

  /tmp/asmcli install \
    --project_id "$PROJECT_ID" \
    --cluster_name "$CLUSTER_NAME" \
    --cluster_location "$CLUSTER_LOCATION" \
    --enable_all \
    --ca mesh_ca
    # the legacy-default-ingress gateway is not deployed, because we need to deploy one that uses
    # an internal load balancer. So the ingress gateway deployment is done manually afterwards
    #--option legacy-default-ingressgateway
    echo
}

deploy_ingressgateway() {
  echo "Deploying Istio IngressGateway for $PROJECT_ID - $CLUSTER_NAME in $SCOPE mode"
  
  echo "Authenticate against the Kubernetes cluster to be able to run kubectl commands"
  gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$CLUSTER_LOCATION"

  # exit if the kubecontext is not set to the cluster name
  kubectl config current-context | grep "gke_${PROJECT_ID}_${CLUSTER_LOCATION}_${CLUSTER_NAME}" || exit 2

  echo "Extracting Anthos Service Mesh revision label"
  rev=$(kubectl get deploy -n istio-system -l app=istiod -o jsonpath={.items[*].metadata.labels.'istio\.io\/rev'}'{"\n"}')

  if [ -z "${rev}" ] ; then
    echo "error: couldn't extract Anthos Service Mesh revision label." 1>&2; exit 1
  fi
  
  echo "Applying label to istio-system namespace"
  kubectl label namespace istio-system istio.io/rev="$rev" --overwrite

  # install the ingress gateway
  kubectl apply -n istio-system -f "./istio-ingressgateway-${SCOPE}"
}

enable_cloud_run_for_anthos() {
  echo "Enabling Cloud Run for Anthos for $PROJECT_ID"
  gcloud container hub cloudrun enable --project="$PROJECT_ID"
  echo "Applying Cloud Run for Anthos on Cluster $PROJECT_ID - $CLUSTER_NAME"
  gcloud container hub cloudrun apply --project="$PROJECT_ID" --gke-cluster="${CLUSTER_LOCATION}/${CLUSTER_NAME}" --config="./cloudrunanthos-${SCOPE}.yaml"
  echo
}

echo -n "glcoud: "; which gcloud
echo -n "kubectl: "; which kubectl

enable_fleet
install_anthos
deploy_ingressgateway
enable_cloud_run_for_anthos