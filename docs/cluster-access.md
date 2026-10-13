# Reaching the EKS API server

The EKS module (`terraform/modules/eks`) controls who can reach the
Kubernetes API endpoint with three inputs:

| Variable | Default | Meaning |
|---|---|---|
| `endpoint_public_access` | `true` | Expose the endpoint on the internet. |
| `endpoint_public_access_cidrs` | `[]` | Source ranges allowed to use the public endpoint. |
| `allow_open_public_endpoint` | `false` | Explicit opt-in to an endpoint open to `0.0.0.0/0`. |

`endpoint_private_access` (default `true`) is unchanged: worker nodes and
anything else inside the VPC reach the API through the private endpoint.

## The guard

When the public endpoint is enabled, AWS treats an empty CIDR list as
`0.0.0.0/0`. The module therefore fails the plan when
`endpoint_public_access = true` and `endpoint_public_access_cidrs` is empty
or contains any `/0` range (`0.0.0.0/0`, `::/0`), unless
`allow_open_public_endpoint = true`. It also rejects:

- both endpoints disabled (nothing could reach the API);
- a CIDR list with the public endpoint disabled (the list would be ignored);
- entries that are not valid CIDR blocks.

These are checked at `terraform plan` time. `terraform test` covers them
with mocked providers (`terraform/modules/eks/tests/eks.tftest.hcl`); they
have not been exercised against a real AWS account.

## The tradeoff

The API server always requires authentication (an IAM identity mapped into
the cluster), so an open endpoint is not an open cluster. It is, however,
reachable by anyone for scanning, for exploiting an API server
vulnerability before you patch it, and for trying leaked credentials. Each
option below gives up some convenience for a smaller attack surface.

### 1. Public endpoint restricted to known CIDRs (recommended for dev)

```hcl
endpoint_public_access_cidrs = ["203.0.113.10/32"] # your egress IP
allow_open_public_endpoint   = false
```

Find your current egress IP with `curl -s https://checkip.amazonaws.com`.
`kubectl` from your laptop works as before:
`aws eks update-kubeconfig --name <cluster_name>`.

Costs: when your IP changes (home ISP, travel, VPN) you must update the list
and re-apply, and CI runners with changing IPs cannot reach the API. If you
ever set `endpoint_private_access = false`, the worker nodes reach the API
through the NAT gateway, so the NAT gateway's Elastic IP(s) must be in the
list too or nodes cannot join.

### 2. Private endpoint only, reached through SSM

```hcl
endpoint_public_access       = false
endpoint_public_access_cidrs = []
allow_open_public_endpoint   = false
```

The API is then only reachable from inside the VPC (or networks connected
to it). This repo does **not** provision a bastion; one way to add the path
yourself:

1. Launch a small EC2 instance in one of the private subnets with an
   instance profile that includes `AmazonSSMManagedInstanceCore`. It needs
   no inbound rules or public IP; the SSM agent connects out through the
   NAT gateway.
2. Allow TCP 443 from that instance's security group to the cluster
   security group (`cluster_security_group_id` output of the eks module).
3. Either run `kubectl` on the instance (`aws ssm start-session --target
   <instance-id>`), or forward the API port to your laptop:

   ```sh
   aws ssm start-session --target <instance-id> \
     --document-name AWS-StartPortForwardingSessionToRemoteHost \
     --parameters host=<endpoint-hostname>,portNumber=443,localPortNumber=8443
   ```

   and point your kubeconfig at `https://localhost:8443` with
   `tls-server-name: <endpoint-hostname>` so the certificate still matches.

The IAM identity you use must be mapped into the cluster; by default only
the identity that created the cluster has admin access.

Costs: an extra instance to run and patch, and every `kubectl`,
`bootstrap-argocd.sh` or `argocd` CLI call has to go through the tunnel.

### 3. Open public endpoint (explicit opt-in)

```hcl
allow_open_public_endpoint = true
```

This is the previous behaviour. With an empty list the module writes
`0.0.0.0/0` explicitly, which is what AWS already stores for a cluster
created without a list, so an existing cluster should see no diff (not
verified against a real cluster).

## The dev environment

`terraform/environments/dev` sets `allow_open_public_endpoint = true` **by
default**, with a comment in `variables.tf` explaining why: so an existing
checkout keeps planning without changing the cluster, and a fresh clone
works without knowing your IP. This is a deliberate opt-in, not a safe
default, and it is not silent: a `check` block prints a warning on every
`plan`/`apply` while the endpoint is open to the internet.

To lock dev down, copy `terraform.tfvars.example` to `terraform.tfvars` (it
is git-ignored) and set your own CIDR list, or switch to option 2.

## Upgrading an existing cluster

- **Using the dev root:** nothing changes until you set variables; you will
  see the warning on each plan.
- **Calling the eks module directly:** the next plan fails with the guard's
  error until you either set `endpoint_public_access_cidrs` or set
  `allow_open_public_endpoint = true` (expected to be a no-op). Failing at plan time is
  intentional: it is better than silently keeping, or silently cutting off,
  access.
- Changing the CIDR list or toggling public/private access goes through
  EKS's cluster-config update rather than recreating the cluster. This
  follows the AWS provider's documented behaviour and has not been tried
  on a real cluster here.
  Restricting access can cut off your own `kubectl`, so put your current IP
  in the list first.
