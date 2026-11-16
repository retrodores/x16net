#!/usr/bin/env python3
"""Record CI publication provenance in a Git note, readable over repository Git."""
import json, os, subprocess, tempfile
from pathlib import Path

def gh(path):
    return subprocess.check_output(["gh","api",path],text=True)

repo=os.environ["GH_REPO"]
tag=os.environ.get("RELEASE_TAG", "v"+Path("VERSION").read_text().strip())
sha=os.environ["GITHUB_SHA"]
run=os.environ.get("RECORD_RUN_ID") or os.environ["GITHUB_RUN_ID"]
if os.environ.get("RECORD_RUN_ID"):
    metadata=json.loads(gh(f"repos/{repo}/actions/runs/{run}"))
    sha=metadata["head_sha"]
    if metadata.get("head_branch", "").startswith("v"):
        tag=metadata["head_branch"]
record={"tag":tag,"source_sha":sha,
        "run_url":f"https://github.com/{repo}/actions/runs/{run}",
        "tests":json.loads(os.environ["TEST_RESULTS"])}
if os.environ.get("RECORD_RUN_ID"):
    record["run_conclusion"]=metadata.get("conclusion")
try:
    release=json.loads(gh(f"repos/{repo}/releases/tags/{tag}"))
    record["release_url"]=release["html_url"]
    record["assets"]=[{"name":a["name"],"size":a["size"],"url":a["browser_download_url"]}
                      for a in release["assets"]]
except subprocess.CalledProcessError:
    record["release_url"]=None
# Capture only completed failing jobs when publication was blocked, for diagnosis
# through the same repository access. GitHub's log endpoint redacts its secrets.
if not record["release_url"]:
    try:
        jobs=json.loads(gh(f"repos/{repo}/actions/runs/{run}/jobs?per_page=100"))["jobs"]
        record["failed_jobs"]=[]
        for job in jobs:
            if job.get("conclusion")=="failure":
                item={"name":job["name"],"url":job["html_url"],
                      "steps":[{"name":s["name"],"conclusion":s.get("conclusion")} for s in job.get("steps",[])]}
                try: item["log_tail"]=gh(f"repos/{repo}/actions/jobs/{job['id']}/logs")[-18000:]
                except subprocess.CalledProcessError: pass
                record["failed_jobs"].append(item)
    except subprocess.CalledProcessError:
        pass
if record.get("failed_jobs"):
    with tempfile.TemporaryDirectory(prefix="x16net-ci-artifacts-") as directory:
        download=subprocess.run(["gh","run","download",run,"--name","network-tests-windows","--dir",directory],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if download.returncode:
            record["diagnostic_artifact_error"]=download.stderr[-4000:]
        else:
            record["diagnostic_files"]={str(p.relative_to(directory)):p.read_text(errors="replace")[-18000:] for p in Path(directory).rglob("*") if p.is_file()}
Path("release-receipt.json").write_text(json.dumps(record,indent=2)+"\n")
subprocess.run(["git","config","user.name","github-actions[bot]"],check=True)
subprocess.run(["git","config","user.email","41898282+github-actions[bot]@users.noreply.github.com"],check=True)
# Preserve earlier release notes; absence of this optional notes ref is normal.
refs=subprocess.check_output(["git","ls-remote","origin","refs/notes/releases"],text=True)
if refs.strip():
    subprocess.run(["git","fetch","origin","refs/notes/releases:refs/notes/releases"],check=True)
subprocess.run(["git","notes","--ref=releases","add","-f","-F","release-receipt.json",sha],check=True)
subprocess.run(["git","push","origin","refs/notes/releases"],check=True)
print("Recorded release publication provenance.")
