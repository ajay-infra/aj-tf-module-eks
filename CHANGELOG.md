# Changelog

All notable changes to this module are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed
- `README.md`'s own Inputs table said `k8s_version` defaults to `1.30`, directly contradicting its own "Version Requirements" section above (which correctly says `1.35`). Checked `variables.tf` — the real default is `"1.35"`. Fixed the stale table row and the stale `1.30`/`1.31` examples elsewhere in `README.md`/`CLAUDE.md`.
- `README.md` / `CLAUDE.md` "Known TODOs" both listed **"EKS access entries (replaces aws-auth ConfigMap)"** as open — it's fully implemented (`e335dd5`, 2026-06-07): 4 real resources in `main.tf` (`aws_eks_access_entry.infra_lead`/`.infra_core`/`.infra_readonly`/`.additional`). Checked off. This was also already documented as done in the central `aj-infra-context/CLAUDE.md` activity log — this repo's own docs just never caught up.
- **"Karpenter NodePool + EC2NodeClass resources"** was listed as a TODO in both files — but per the platform's own architecture, those CRDs are GitOps-managed in `k8s-manifests`, never Terraform resources in this module. Confirmed zero Karpenter/NodePool resources anywhere in this repo's `.tf` files. Removed from the TODO list with an explanatory note, rather than left as pending work that will never be "done" here.
- `README.md` / `CLAUDE.md` Terraform version corrected `1.7.5` → `1.10.5`, matching `providers.tf`'s actual pin (bumped in `9efb193`, part of the platform-wide Terraform 1.10.5 / S3-native-locking migration).
- `README.md` / `CLAUDE.md` "Running Locally" pointed at `My-Infra/ make shell` — repo since renamed to `aj-infra-context`; that Podman workflow currently has no `Makefile`/`Dockerfile` (documented gap, not fixed here). Updated the reference and noted the gap inline.
- `skills.md` had a wrong org in its stable ref (`github.com/ajaylakma/...` → `github.com/ajay-infra/...`) and a stale branch convention (`eks-01` → the real `v1.0.0` tag) — same pattern already found and fixed in `aj-tf-module-scps`'s `skills.md`.
- `skills.md` used `blue-green` (hyphen) for `eks_deployment_mode` in two places — the real value used everywhere in code and docs is `blue_green` (underscore).
- `skills.md`'s "AWS tags applied" listed `Env`, `ManagedBy`, `Model`, `Customer` — none of which exist. Checked `locals.tf`: real tags are `Environment` (not `Env`), `Team`, `CostCenter`, `ClusterName`, `AZCount` (the last two were missing from the list entirely).
- `CLAUDE.md` narrowed the module's own description to "optimized for AI inference workloads" — GPU node groups are one optional node-group configuration among several, not the module's defining purpose. Generalized to match the module's actual reusable design (same reasoning as the equivalent fix in `aj-tf-module-vpc`).

## [v1.0.0] - 2026-05-16

Initial release — EKS cluster, dynamic node groups, Pod Identity, Cilium CNI support, blue/green deployment mode, `az_count` 2/3/4.
