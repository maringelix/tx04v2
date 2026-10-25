<# tx04v2 Docker-only launcher. Host requirement: Docker Desktop only. #>
# Use PowerShell's automatic $args instead of a param block so flags such as
# kubectl's -o/-A pass through without PowerShell trying to bind them itself.
$Command = if ($args.Count -gt 0) { [string]$args[0] } else { 'help' }
$Arguments = if ($args.Count -gt 1) { [string[]]$args[1..($args.Count - 1)] } else { [string[]]@() }

# Reject unsupported commands before inspecting Docker or building the toolbox.
$SupportedCommands = @('help', 'build', 'up', 'up-cilium', 'down', 'gpu', 'scheduling', 'serving', 'networking', 'observability', 'kwok', 'scale', 'kubectl', 'helm', 'run', 'grafana', 'prometheus')
if ($Command -cnotin $SupportedCommands) {
  [Console]::Error.WriteLine("Unknown command '$Command'. Run .\lab.ps1 help.")
  exit 2
}
if ($Command -eq 'down' -and $env:TX04V2_ACK_DELETE_CLUSTER -ne 'tx04v2') {
  [Console]::Error.WriteLine('Refusing to delete the tx04v2 cluster without TX04V2_ACK_DELETE_CLUSTER=tx04v2.')
  exit 2
}

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$StateDir = Join-Path $RepoRoot '.state'
$ToolboxImage = 'tx04v2-toolbox:local'

function Assert-Docker {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker was not found. Install/start Docker Desktop; no other host tool is required.'
  }
  docker info *> $null
  if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is installed but its daemon is not running.' }
}

function Build-Toolbox {
  Write-Host '>> Building the containerized toolchain (kind + kubectl + Helm)...'
  docker build -f (Join-Path $RepoRoot 'Dockerfile.toolbox') -t $ToolboxImage $RepoRoot
  if ($LASTEXITCODE -ne 0) { throw 'Failed to build the tx04v2 toolbox image.' }
}

function Ensure-Toolbox {
  docker image inspect $ToolboxImage *> $null
  if ($LASTEXITCODE -ne 0) { Build-Toolbox }
}

function Invoke-Toolbox {
  param(
    [Parameter(Mandatory = $true, Position = 0)][string[]]$ToolArguments,
    [string[]]$Publish = @()
  )
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  $dockerArgs = @(
    'run', '--rm', '-i',
    '--volume', '/var/run/docker.sock:/var/run/docker.sock',
    '--volume', "${RepoRoot}:/workspace",
    '--volume', "${StateDir}:/state"
  )
  docker network inspect kind *> $null
  if ($LASTEXITCODE -eq 0) { $dockerArgs += @('--network', 'kind') }
  foreach ($port in $Publish) { $dockerArgs += @('--publish', "127.0.0.1:$port") }
  $dockerArgs += $ToolboxImage
  $dockerArgs += $ToolArguments
  & docker @dockerArgs
  if ($LASTEXITCODE -ne 0) { throw "Toolbox command failed with exit code $LASTEXITCODE." }
}

function Export-Kubeconfig {
  Invoke-Toolbox @('kind', 'export', 'kubeconfig', '--name', 'tx04v2', '--internal', '--kubeconfig', '/state/kubeconfig')
}

function Start-Cluster([string]$Variant) {
  $config = if ($Variant -eq 'cilium') {
    '/workspace/clusters/kind/kind-cluster-cilium.yaml'
  } else {
    '/workspace/clusters/kind/kind-cluster.yaml'
  }
  $exists = docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq 'tx04v2-control-plane' }
  if (-not $exists) {
    Invoke-Toolbox @('kind', 'create', 'cluster', '--name', 'tx04v2', '--config', $config, '--wait', '0s')
  } else {
    Write-Host ">> Cluster 'tx04v2' already exists."
  }
  Export-Kubeconfig
  if ($Variant -eq 'cilium') {
    Invoke-Toolbox @('bash', 'platform/40-networking/install.sh')
  } else {
    Invoke-Toolbox @('kubectl', 'wait', '--for=condition=Ready', 'nodes', '--all', '--timeout=180s')
  }
  Invoke-Toolbox @('kubectl', 'get', 'nodes', '-o', 'wide')
}

function Show-Help {
  @'
tx04v2 — Docker-only Kubernetes AI/GPU lab

Host requirement: Docker Desktop only. Nothing else is installed on the host.

  .\lab.ps1 build                 Build the containerized toolchain
  .\lab.ps1 up                    Create the default kind cluster
  .\lab.ps1 up-cilium             Create the Cilium/eBPF cluster
  $env:TX04V2_ACK_DELETE_CLUSTER='tx04v2'; .\lab.ps1 down
                                   Delete the lab cluster in an explicit window
  .\lab.ps1 gpu                   Install the simulated GPU operator
  .\lab.ps1 scheduling            Install Volcano
  .\lab.ps1 serving               Deploy the mock LLM
  .\lab.ps1 networking            Install default-cluster network add-ons
  .\lab.ps1 observability         Install Prometheus and Grafana
  .\lab.ps1 kwok [count]          Create fake GPU nodes (default: 100)
  .\lab.ps1 scale                 Submit the 400-pod scale workload
  .\lab.ps1 kubectl <args...>     Run kubectl inside the toolbox
  .\lab.ps1 helm <args...>        Run Helm inside the toolbox
  .\lab.ps1 run <command...>      Run any toolbox command
  .\lab.ps1 grafana               Forward Grafana to localhost:3001 (admin/admin)
  .\lab.ps1 prometheus            Forward Prometheus to localhost:9090
'@ | Write-Host
}

if ($Command -ne 'help') {
  Assert-Docker
  if ($Command -ne 'build') { Ensure-Toolbox }
}

switch ($Command) {
  'help'          { Show-Help }
  'build'         { Build-Toolbox }
  'up'            { Start-Cluster 'default' }
  'up-cilium'     { Start-Cluster 'cilium' }
  'down'          {
    Invoke-Toolbox @('kind', 'delete', 'cluster', '--name', 'tx04v2')
    Remove-Item (Join-Path $StateDir 'kubeconfig') -Force -ErrorAction SilentlyContinue
  }
  'gpu'           { Invoke-Toolbox @('bash', 'platform/10-gpu/install.sh') }
  'scheduling'    { Invoke-Toolbox @('bash', 'platform/20-scheduling/install.sh') }
  'serving'       { Invoke-Toolbox @('kubectl', 'apply', '-f', 'platform/30-serving/mock-llm.yaml') }
  'networking'    {
    Invoke-Toolbox @('bash', 'platform/40-networking/nodelocaldns-install.sh')
    Invoke-Toolbox @('kubectl', 'apply', '-f', 'platform/40-networking/conntrack-tuning.yaml')
    Invoke-Toolbox @('kubectl', 'apply', '-f', 'platform/40-networking/netpol.yaml')
  }
  'observability' { Invoke-Toolbox @('bash', 'platform/50-observability/install.sh') }
  'kwok'          {
    $count = if ($Arguments.Count -gt 0) { $Arguments[0] } else { '100' }
    Invoke-Toolbox @('bash', 'clusters/kwok/install.sh')
    Invoke-Toolbox @('bash', 'clusters/kwok/create-fake-nodes.sh', $count)
  }
  'scale'         { Invoke-Toolbox @('kubectl', 'apply', '-f', 'clusters/kwok/scale-workload.yaml') }
  'kubectl'       { Invoke-Toolbox (@('kubectl') + $Arguments) }
  'helm'          { Invoke-Toolbox (@('helm') + $Arguments) }
  'run'           { Invoke-Toolbox $Arguments }
  'grafana'       { Invoke-Toolbox @('kubectl', '-n', 'monitoring', 'port-forward', '--address=0.0.0.0', 'svc/kube-prom-grafana', '3001:80') -Publish @('3001:3001') }
  'prometheus'    { Invoke-Toolbox @('kubectl', '-n', 'monitoring', 'port-forward', '--address=0.0.0.0', 'svc/kube-prom-prometheus', '9090:9090') -Publish @('9090:9090') }
  default         { throw "Unknown command '$Command'. Run .\lab.ps1 help." }
}
