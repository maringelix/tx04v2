#!/usr/bin/env python3
"""Hosted-CI checks and synthetic fixtures for the standalone lab."""

import json
from pathlib import Path
import re

import yaml


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".ci-generated"
OUT.mkdir(exist_ok=True)

# Broken relative documentation links would leave the extracted lab unusable.
for document in ROOT.rglob("*.md"):
    if ".git" in document.parts:
        continue
    for link in re.findall(r"\]\(([^\s)]+)\)", document.read_text()):
        if "://" in link or link.startswith(("#", "mailto:")):
            continue
        target = link.split("#", 1)[0]
        if target:
            assert (document.parent / target).exists(), (document, link)

rule_file = ROOT / "platform/50-observability/prometheusrule-gpu.yaml"
rules = yaml.safe_load(rule_file.read_text())["spec"]
(OUT / "rules.yaml").write_text(yaml.safe_dump(rules, sort_keys=False))

dashboard_file = ROOT / "platform/50-observability/grafana-dashboard-gpu.yaml"
dashboard_data = yaml.safe_load(dashboard_file.read_text())["data"]
expressions = []
for value in dashboard_data.values():
    dashboard = json.loads(value)
    assert dashboard["panels"], "Dashboard must contain panels"
    for panel in dashboard["panels"]:
        for target in panel.get("targets", []):
            if "expr" in target:
                expressions.append(target["expr"])
assert expressions, "Dashboard must query metrics"
dashboard_rules = {
    "groups": [{"name": "dashboard.syntax", "rules": [
        {"record": f"lab_dashboard_expression_{i}", "expr": expression}
        for i, expression in enumerate(expressions)
    ]}]
}
(OUT / "dashboard-rules.yaml").write_text(yaml.safe_dump(dashboard_rules, sort_keys=False))

# Exercise the GPU alert's pending interval, firing labels and recovery with
# synthetic metrics. No GPU, private endpoint or cloud account is needed.
gpu_rule = next(rule for group in rules["groups"] for rule in group["rules"]
                if rule.get("alert") == "GPUVRAMNearExhaustion")
assert gpu_rule["for"] == "5m"
expected = {
    "exp_labels": {"gpu": "0", "Hostname": "lab-node", "severity": "warning"},
    "exp_annotations": {
        key: value.replace("{{ $labels.gpu }}", "0").replace("{{ $labels.Hostname }}", "lab-node")
        for key, value in gpu_rule["annotations"].items()
    },
}
fixtures = {
    "rule_files": ["rules.yaml"],
    "evaluation_interval": "1m",
    "tests": [{
        "interval": "1m",
        "input_series": [
            {"series": 'DCGM_FI_DEV_FB_USED{gpu="0",Hostname="lab-node"}', "values": "95+0x7 20+0x2"},
            {"series": 'DCGM_FI_DEV_FB_FREE{gpu="0",Hostname="lab-node"}', "values": "5+0x7 80+0x2"},
        ],
        "alert_rule_test": [
            {"eval_time": "4m", "alertname": "GPUVRAMNearExhaustion", "exp_alerts": []},
            {"eval_time": "5m", "alertname": "GPUVRAMNearExhaustion", "exp_alerts": [expected]},
            {"eval_time": "8m", "alertname": "GPUVRAMNearExhaustion", "exp_alerts": []},
        ],
    }],
}
(OUT / "rule-tests.yaml").write_text(yaml.safe_dump(fixtures, sort_keys=False))
print("Documentation links, dashboard JSON and synthetic rule fixtures validated.")
