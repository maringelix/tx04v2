# Working on tx04v2

Read [the maintenance guide](docs/MAINTENANCE.md) and
[the validation harness](docs/HARNESS.md) before changing the lab.

- This repository is an educational Kubernetes AI/GPU lab for a disposable
  machine or a hosted CI runner. Use synthetic workloads and data only.
- The host prerequisite is Docker Desktop. The launchers run kind, kubectl,
  Helm and other lab tools inside the toolbox; keep host configuration untouched.
- Run builds, dependency installations and test suites only on a disposable lab
  machine or a hosted runner. A separate container does not isolate host memory,
  disk capacity or the Docker daemon from other workloads.
- Keep the cluster name `tx04v2`, toolbox image `tx04v2-toolbox:local` and ignored
  `.state/` directory consistent across launchers, manifests and documentation.
- Destructive actions must target the exact lab cluster. Teardown requires
  `TX04V2_ACK_DELETE_CLUSTER=tx04v2`; never use global Docker prune commands.
- Do not add organization-specific integrations, private endpoints, credentials,
  customer data or workstation paths. Use reserved example domains and synthetic
  identifiers when examples need values.
- Preserve the distinction between simulated GPUs, KWOK nodes and real hardware.
  Do not describe configuration or a passing static check as a runtime result.
- Keep dependency versions explicit. Update code, validation and documentation
  together when changing the toolchain or Kubernetes resource contracts.
- Keep public documentation and examples in English. Preserve the MIT license.
- Changes should pass the checks for their exact revision before merging. Diagnose
  failures instead of suppressing checks or claiming an unexecuted validation.
