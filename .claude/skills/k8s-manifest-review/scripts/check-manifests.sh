#!/usr/bin/env bash
# Lightweight static checks for rendered Kubernetes YAML.
# Usage: check-manifests.sh <rendered.yaml>
# Exits 1 if any HIGH/CRITICAL finding exists.
set -euo pipefail

file="${1:?usage: check-manifests.sh <rendered.yaml>}"
python3 - "$file" <<'PY'
import sys, yaml

fails = 0
def report(sev, res, msg):
    global fails
    if sev in ("CRITICAL", "HIGH"):
        fails += 1
    print(f"{sev:8} | {res:40} | {msg}")

with open(sys.argv[1]) as fh:
    docs = [d for d in yaml.safe_load_all(fh) if d]

# The same kind/namespace/name twice makes `helm install` fail; kubeconform
# validates each document alone and cannot see it.
seen = set()
for doc in docs:
    meta = doc.get("metadata") or {}
    key = (doc.get("kind", ""), meta.get("namespace", ""), meta.get("name", ""))
    if key in seen:
        report("HIGH", f"{key[0]}/{key[2]}", "duplicate resource (same kind and name)")
    seen.add(key)

workload_kinds = {"Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"}
for doc in docs:
    kind = doc.get("kind", "")
    if kind not in workload_kinds:
        continue
    name = f"{kind}/{doc['metadata']['name']}"
    spec = doc["spec"]
    if kind == "CronJob":
        spec = spec["jobTemplate"]["spec"]
    pod = spec["template"]["spec"]
    psc = pod.get("securityContext", {})
    for c in pod.get("containers", []):
        cname = f"{name}:{c['name']}"
        image = c.get("image", "")
        if ":" not in image.split("/")[-1] or image.endswith(":latest"):
            report("HIGH", cname, f"image not pinned ({image})")
        res = c.get("resources", {})
        for k in ("requests", "limits"):
            if not res.get(k):
                report("HIGH", cname, f"missing resources.{k}")
        for p in ("readinessProbe", "livenessProbe"):
            if p not in c:
                report("MEDIUM", cname, f"missing {p}")
        sc = c.get("securityContext", {})
        if not (sc.get("runAsNonRoot") or psc.get("runAsNonRoot")):
            report("CRITICAL", cname, "runAsNonRoot not set")
        if not sc.get("readOnlyRootFilesystem"):
            report("MEDIUM", cname, "readOnlyRootFilesystem not true")
        if sc.get("allowPrivilegeEscalation", True):
            report("HIGH", cname, "allowPrivilegeEscalation not false")
        if sc.get("privileged"):
            report("CRITICAL", cname, "privileged container")

print(f"\n{len(docs)} documents checked, {fails} HIGH/CRITICAL findings")
sys.exit(1 if fails else 0)
PY
