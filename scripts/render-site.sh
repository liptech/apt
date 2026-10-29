#!/usr/bin/env bash
#
# Renderiza site/index.template.html em <out>/index.html, preenchendo os
# placeholders e a tabela de pacotes lida dos indices ja gerados.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?uso: render-site.sh <dir-de-saida>}"

# shellcheck source=../repo.conf
source "$ROOT/repo.conf"

export OUT ROOT ORIGIN LABEL SUITE CODENAME COMPONENTS ARCHITECTURES \
       DESCRIPTION DOMAIN KEYRING_NAME GITHUB_REPO

python3 - <<'PY'
import glob, html, os, pathlib, datetime

out  = pathlib.Path(os.environ["OUT"])
root = pathlib.Path(os.environ["ROOT"])
env  = os.environ

def parse_packages(path):
    """Le um arquivo Packages e devolve uma lista de dicts."""
    stanzas = []
    for block in pathlib.Path(path).read_text(encoding="utf-8").split("\n\n"):
        if not block.strip():
            continue
        fields, key = {}, None
        for line in block.splitlines():
            if line[:1] in (" ", "\t") and key:
                fields[key] += "\n" + line.strip()
            elif ":" in line:
                key, _, val = line.partition(":")
                fields[key.strip()] = val.strip()
        if fields.get("Package"):
            stanzas.append(fields)
    return stanzas

pkgs = []
for f in sorted(glob.glob(str(out / "dists" / env["SUITE"] / "*" / "binary-*" / "Packages"))):
    pkgs.extend(parse_packages(f))

# Pacotes "all" aparecem no indice de toda arquitetura: lista cada um uma vez.
seen, unique = set(), []
for p in pkgs:
    key = (p["Package"], p.get("Version", ""), p.get("Architecture", ""))
    if key not in seen:
        seen.add(key)
        unique.append(p)
pkgs = unique
pkgs.sort(key=lambda p: (p["Package"], p.get("Architecture", ""), p.get("Version", "")))

def human(n):
    n = int(n)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n/1:.1f} {unit}"
        n /= 1024
    return f"{n} GB"

def size(p):
    try:
        b = int(p.get("Size", 0))
    except ValueError:
        return "-"
    for unit in ("B", "KB", "MB", "GB"):
        if b < 1024:
            return f"{b:.0f} {unit}" if unit == "B" else f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} TB"

rows = []
for p in pkgs:
    desc = html.escape(p.get("Description", "").split("\n")[0])
    rows.append(
        "        <tr>\n"
        f'          <td class="pkg">{html.escape(p["Package"])}</td>\n'
        f'          <td><code>{html.escape(p.get("Version","-"))}</code></td>\n'
        f'          <td><span class="arch">{html.escape(p.get("Architecture","-"))}</span></td>\n'
        f'          <td class="desc">{desc}</td>\n'
        f'          <td class="num">{size(p)}</td>\n'
        f'          <td><a href="{html.escape(p.get("Filename","#"))}">.deb</a></td>\n'
        "        </tr>"
    )

if rows:
    table = "\n".join(rows)
else:
    table = ('        <tr><td colspan="6" class="empty">'
             "Nenhum pacote publicado ainda.</td></tr>")

# assets estaticos (logos, icones)
import shutil
src_assets = root / "site" / "assets"
if src_assets.is_dir():
    shutil.copytree(src_assets, out / "assets", dirs_exist_ok=True)

# fingerprint da chave publica exportada pelo build
fingerprint = "chave nao disponivel"
asc = out / f"{env['KEYRING_NAME']}.asc"
if asc.exists():
    import subprocess
    try:
        res = subprocess.run(
            ["gpg", "--with-colons", "--import-options", "show-only",
             "--import", str(asc)],
            capture_output=True, text=True, check=True)
        for line in res.stdout.splitlines():
            if line.startswith("fpr:"):
                raw = line.split(":")[9]
                fingerprint = " ".join(raw[i:i+4] for i in range(0, len(raw), 4))
                break
    except Exception:
        pass

tpl = (root / "site" / "index.template.html").read_text(encoding="utf-8")
repl = {
    "{{DOMAIN}}":     env["DOMAIN"],
    "{{KEYRING}}":    env["KEYRING_NAME"],
    "{{SUITE}}":      env["SUITE"],
    "{{COMPONENTS}}": env["COMPONENTS"],
    "{{ARCHS}}":      ", ".join(env["ARCHITECTURES"].split()),
    "{{ORIGIN}}":     env["ORIGIN"],
    "{{REPO}}":       env.get("GITHUB_REPO", ""),
    "{{PACKAGES}}":   table,
    "{{PKGCOUNT}}":   str(len(pkgs)),
    "{{FINGERPRINT}}": fingerprint,
    "{{KEYID}}":      fingerprint.replace(" ", "")[-16:] if fingerprint[0].isalnum() and " " in fingerprint else "-",
    "{{KEYUID}}":     "LIPTECH Archive Signing Key &lt;liptech@gmail.com&gt;",
    "{{UPDATED}}":    datetime.datetime.now(datetime.timezone.utc)
                              .strftime("%Y-%m-%d %H:%M UTC"),
}
for k, v in repl.items():
    tpl = tpl.replace(k, v)

(out / "index.html").write_text(tpl, encoding="utf-8")

# setup.sh e CNAME: tambem passam pelos placeholders.
for name in ("setup.sh", "CNAME", ".nojekyll"):
    src = root / "site" / name
    if src.exists():
        text = src.read_text(encoding="utf-8")
        for k, v in repl.items():
            text = text.replace(k, v)
        dst = out / name
        dst.write_text(text, encoding="utf-8")
        if name.endswith(".sh"):
            dst.chmod(0o755)

# pagina /admin, com os mesmos placeholders
admin_src = root / "site" / "admin" / "index.template.html"
if admin_src.exists():
    at = admin_src.read_text(encoding="utf-8")
    for k, v in repl.items():
        at = at.replace(k, v)
    # CSP: hash do script ja substituido, para script-src estrito
    import base64, hashlib, re
    m = re.search(r"<script>(.*?)</script>", at, re.S)
    if m:
        h = base64.b64encode(hashlib.sha256(m.group(1).encode("utf-8")).digest()).decode()
        at = at.replace("{{CSP_SCRIPT_HASH}}", "sha256-" + h)
    (out / "admin").mkdir(parents=True, exist_ok=True)
    (out / "admin" / "index.html").write_text(at, encoding="utf-8")
    print("    admin/index.html")

# 404 simples, se existir
src = root / "site" / "404.html"
if src.exists():
    (out / "404.html").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")

print(f"    index.html com {len(pkgs)} pacote(s)")
PY
