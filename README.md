**Please be aware:** this is not an official code sample or project. It is provided for illustrative purposes only.

# cloud-run-gke

Simple script that helps with the installation of Cloud Run for Anthos on a GKE Cluster

The script executes the follwoing steps:
 1. register a GKE cluster to Anthos Fleets
 2. install Anthos Service Mesh 1.12 in-cluster control plane
 3. deploy [Istio IngressGateway](https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages/tree/main/samples/gateways/istio-ingressgateway) in private/public mode
 4. enable Cloud Run for Anthos in private/public mode

This script expects the following tools to be installed
- `curl`
- `gcloud`
- `kubectl`

Additionally kubectl access to the GKE cluster from the machine is required.

It works for GKE private or public clusters

## Script based execution

Requirements:
- GKE cluster deployed (_Anthos Service Mesh requires at least 8 vCPUs. If the machine type has 4 vCPUs, your cluster must have at least 2 nodes. If the machine type has 8 vCPUs, the cluster only needs 1 node. If you need to add nodes, see Resizing a cluster._)
- Linux machine with required tools availble (e.g. **Google Cloud Shell**)
- Access from Linux machine to Kubernetes API of GKE cluster (via `gcloud`)

**Important:** for **private clusters** an existing firewall rule needs to be updated before deploying the Istio IngressGateway
```
# find firewall rule in format gke-CLUSTER_NAME-jskdsjd-master
rule=$(gcloud compute firewall-rules list --format='table(name)' | egrep "gke-${CLUSTER_NAME}-[^-]*-master")
gcloud compute firewall-rules update "$rule" --allow tcp:10250,tcp:443,tcp:15017
```
without opening `tcp:15017` the istio-ingressgateway replicaset will not create any pods.

```
# clone the repository
git clone https://github.com/mrbuk/cloud-run-gke && cd cloud-run-gke

# private cluster - deploys Istio Ingress Gateway with Private LB-IP
./enable_cloudrun.sh -p my-project-abc -c internal-cluster -l europe-west1-c -s private

# public cluster - deploys Istio Ingress Gateway with Public LB-IP
./enable_cloudrun.sh -p my-project-abc -c external-cluster -l europe-west1-c -s public
```

Afterwards you should be able to deploy to Cloud Run e.g.

```
gcloud run deploy internal-01 --image gcr.io/cloudrun/hello --cluster=internal-cluster

gcloud run deploy external-01 --image gcr.io/cloudrun/hello --cluster=external-cluster
```

## Manual execution

If you prefer to run the commands manually instead of using `enable_cloudrun.sh`:

```
# register cluster with fleet
gcloud container hub memberships register "${CLUSTER_NAME}" --project="$PROJECT_ID" --gke-cluster="${CLUSTER_LOCATION}/${CLUSTER_NAME}" --enable-workload-identity

# deploy Anthos Service Mesh
curl https://storage.googleapis.com/csm-artifacts/asm/asmcli_1.12 > /tmp/asmcli
chmod +x /tmp/asmcli

/tmp/asmcli install \
  --project_id "$PROJECT_ID" \
  --cluster_name "$CLUSTER_NAME" \
  --cluster_location "$CLUSTER_LOCATION" \
  --enable_all \
  --ca mesh_ca

# install Istio Ingress Gateway
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$CLUSTER_LOCATION"

rev=$(kubectl get deploy -n istio-system -l app=istiod -o jsonpath={.items[*].metadata.labels.'istio\.io\/rev'}'{"\n"}')
kubectl label namespace istio-system istio.io/rev="$rev" --overwrite

kubectl apply -n istio-system -f "./istio-ingressgateway-${SCOPE}"

# enable Cloud Run for Anthos on project
gcloud container hub cloudrun enable --project="$PROJECT_ID"

# apply Cloud Run for Anthos on cluster
gcloud container hub cloudrun apply --project="$PROJECT_ID" --gke-cluster="${CLUSTER_LOCATION}/${CLUSTER_NAME}" --config="./cloudrunanthos-${SCOPE}.yaml"
```

## Documentation

- [Cloud Run for Anthos - Custom installation](https://cloud.google.com/anthos/run/docs/install/on-gcp/custom)
- [Anthos Service Mesh - Quickstart](https://cloud.google.com/service-mesh/docs/unified-install/quickstart-asm#revision-label)