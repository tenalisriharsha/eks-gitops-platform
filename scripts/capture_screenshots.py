#!/usr/bin/env python3
"""Regenerate docs/screenshots/*.png from real runs of this repository's own commands.

Every image is produced by executing the exact command shown in it from the repository root and
capturing its real stdout+stderr and exit code; nothing is typed, edited or shortened by hand. Each
capture is also saved as a .txt transcript next to the image.

Requirements: Terraform, Helm, Ruby, Python 3 (stdlib only) and Chromium's headless shell (set
CHROME=/path/to/headless_shell if it is not found automatically). No AWS account is used: the
Terraform tests run against a mocked provider.

Usage: python3 scripts/capture_screenshots.py
"""
import glob
import html
import os
import subprocess
import sys
import tempfile
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "screenshots")
WIDTH = 1040
COLS = 118

# (file stem, window title, command run from the repository root)
SHOTS = [
    ("01-validate-all", "fmt, validate and test every Terraform root and module",
     "TF_CLI_ARGS=-no-color ./scripts/validate.sh 2>&1 | tail -16"),
    ("02-dev-environment-test", "the dev environment, planned against a mocked AWS provider",
     "terraform -chdir=terraform/environments/dev test -no-color"),
    ("03-irsa-test", "IRSA module: trust policy scoped to one service account",
     "terraform -chdir=terraform/modules/irsa test -no-color"),
    ("04-gitops-checks", "GitOps manifest checks and an ArgoCD helm template",
     "./scripts/validate-gitops.sh"),
    ("05-app-of-apps-root", "the ArgoCD root application (app of apps)",
     "cat gitops/argocd/root-app.yaml"),
    ("06-child-application", "one child application the root deploys",
     "cat gitops/apps/backend-app.yaml"),
    ("07-check-drift-help", "scripts/check-drift.sh: scheduled sync/health reporting",
     "./scripts/check-drift.sh --help"),
]

PAGE = """<!doctype html><meta charset="utf-8"><style>
html,body{{margin:0;background:#0b0e14}}
.win{{width:{w}px;box-sizing:border-box;background:#0f131c;border:1px solid #262c3a;border-radius:10px;overflow:hidden;
font-family:"SF Mono",Menlo,Consolas,"DejaVu Sans Mono",monospace}}
.bar{{display:flex;align-items:center;gap:8px;padding:10px 14px;background:#181d2a;border-bottom:1px solid #262c3a}}
.dot{{width:12px;height:12px;border-radius:50%}}.title{{margin-left:8px;color:#8b93a7;font-size:12.5px}}
.exit{{margin-left:auto;font-size:12px;padding:2px 8px;border-radius:10px}}
.ok{{color:#7ee2a8;background:#123324}}.bad{{color:#ffb4a8;background:#3a1a17}}
pre{{margin:0;padding:16px 18px 20px;color:#d6dbe8;font:13.5px/1.5 "SF Mono",Menlo,Consolas,"DejaVu Sans Mono",monospace;
white-space:pre-wrap;word-break:break-all}}.p{{color:#7ee2a8}}.c{{color:#fff;font-weight:600}}
</style><div class="win"><div class="bar"><span class="dot" style="background:#ff5f57"></span>
<span class="dot" style="background:#febc2e"></span><span class="dot" style="background:#28c840"></span>
<span class="title">{title}</span><span class="exit {cls}">exit code {code}</span></div>
<pre><span class="p">$ </span><span class="c">{cmd}</span>
{out}</pre></div>"""


def find_chrome():
    if os.environ.get("CHROME"):
        return os.environ["CHROME"]
    for base in ("~/Library/Caches/ms-playwright", "~/.cache/ms-playwright"):
        for pat in ("chromium_headless_shell-*/chrome-headless-shell-mac-arm64/chrome-headless-shell",
                    "chromium_headless_shell-*/chrome-mac/headless_shell",
                    "chromium_headless_shell-*/chrome-linux/headless_shell"):
            found = sorted(glob.glob(os.path.join(os.path.expanduser(base), pat)))
            if found:
                return found[-1]
    sys.exit("headless Chromium not found; set CHROME=/path/to/headless_shell")


def wrapped_lines(text):
    return sum(max(1, len(textwrap.wrap(line, COLS, drop_whitespace=False)) or 1) for line in text.split("\n"))


def main():
    chrome = find_chrome()
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, "*")):
        os.remove(old)
    # not shown in any image: make sure the providers are initialised (offline, no backend)
    for d in ("terraform/environments/dev", "terraform/modules/irsa"):
        subprocess.run(["terraform", "-chdir=" + d, "init", "-input=false", "-backend=false", "-no-color"],
                       cwd=ROOT, capture_output=True, check=True)
    for stem, title, cmd in SHOTS:
        r = subprocess.run(["bash", "-c", cmd], cwd=ROOT, capture_output=True, text=True)
        out = (r.stdout + r.stderr).rstrip("\n")
        with open(os.path.join(OUT, stem + ".txt"), "w") as f:
            f.write("$ " + cmd + "\n" + out + "\n")
        page = PAGE.format(w=WIDTH, title=html.escape(title), cls="ok" if r.returncode == 0 else "bad",
                           code=r.returncode, cmd=html.escape(cmd), out=html.escape(out))
        height = int((wrapped_lines("$ " + cmd) + wrapped_lines(out)) * 20.25) + 90
        with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as t:
            t.write(page)
        subprocess.run([chrome, "--headless", "--no-sandbox", "--hide-scrollbars", "--force-device-scale-factor=2",
                        f"--window-size={WIDTH},{height}", f"--screenshot={os.path.join(OUT, stem + '.png')}",
                        "file://" + t.name], capture_output=True, check=True)
        os.unlink(t.name)
        print(f"captured {stem} (exit {r.returncode})")


if __name__ == "__main__":
    main()
