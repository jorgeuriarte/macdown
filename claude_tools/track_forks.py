#!/usr/bin/env python3
"""
track_forks.py — Rastrea el ecosistema de forks de MacDown.

Para cada "seed" listado en claude_tools/seeds.txt (el MacDown original + los
forks evolucionados/migrados que nos interesan), este script:

  1. Lista los forks del seed (paginado).
  2. Se queda con los que tienen actividad POSTERIOR al último push del seed
     (filtro barato que descarta miles de clones muertos sin compararlos).
  3. Compara cada candidato con el seed para saber cuántos commits propios
     tiene (ahead) y recoge los títulos de esos commits.

Genera dos salidas:
  - docs/FORKS.md                  informe legible (lo que aporta cada fork)
  - claude_tools/forks_state.json  snapshot estructurado

Si ya existe un snapshot previo, calcula el DELTA (forks nuevos y forks con
commits nuevos desde la última ejecución) y lo destaca al principio del informe.
Así "detectar nuevos forks que aparezcan" es simplemente: volver a ejecutarlo.

Requisitos: la CLI `gh` autenticada (usa tu sesión de GitHub).

Uso:
    python3 claude_tools/track_forks.py                # rastrea y escribe salidas
    python3 claude_tools/track_forks.py --dry-run      # no escribe nada, solo resumen
    python3 claude_tools/track_forks.py --seeds f.txt  # otra lista de seeds
"""

import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SEEDS = os.path.join(ROOT, "claude_tools", "seeds.txt")
DEFAULT_STATE = os.path.join(ROOT, "claude_tools", "forks_state.json")
DEFAULT_REPORT = os.path.join(ROOT, "docs", "FORKS.md")

# Máximo de comparaciones concurrentes (la API de GitHub aguanta de sobra,
# pero limitamos para ser educados y evitar timeouts en redes lentas).
MAX_WORKERS = 6
# Máximo de títulos de commit que guardamos por fork en el informe.
MAX_COMMITS = 60


# --------------------------------------------------------------------------- #
# Helpers de la API de GitHub vía `gh`
# --------------------------------------------------------------------------- #
def _run_gh(args, retries=4):
    """Ejecuta `gh <args>` con reintentos ante errores transitorios de red."""
    err = ""
    for attempt in range(retries):
        proc = subprocess.run(["gh", *args], capture_output=True, text=True)
        if proc.returncode == 0:
            return proc.stdout
        err = proc.stderr.strip()
        # Errores no transitorios: no insistir.
        if any(code in err for code in ("Not Found", "404", "422", "451")):
            raise LookupError(err)
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(err or "gh falló sin mensaje")


def gh_object(path, jq):
    """Una llamada a la API que devuelve un único objeto JSON."""
    out = _run_gh(["api", path, "--jq", jq])
    return json.loads(out)


def gh_ndjson(path, jq):
    """Llamada paginada cuyo --jq emite un objeto compacto por línea (NDJSON)."""
    out = _run_gh(["api", "--paginate", path, "--jq", jq])
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


# --------------------------------------------------------------------------- #
# Núcleo del tracking
# --------------------------------------------------------------------------- #
def parse_seed(spec):
    """'owner/repo' o 'owner/repo:branch' -> (repo, branch_or_None)."""
    if ":" in spec:
        repo, branch = spec.split(":", 1)
        return repo.strip(), branch.strip()
    return spec.strip(), None


def load_seeds(path):
    seeds = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            seeds.append(line)
    return seeds


def compare_fork(seed_repo, seed_owner, seed_branch, fork):
    """Compara un fork con su seed. Devuelve (fork, info|None)."""
    fork_owner = fork["full_name"].split("/")[0]
    fork_branch = fork.get("default_branch") or "master"
    basehead = f"{seed_owner}:{seed_branch}...{fork_owner}:{fork_branch}"
    jq = ('{ahead:.ahead_by, behind:.behind_by, status:.status, '
          'commits:[.commits[].commit.message | split("\\n")[0]]}')
    try:
        res = gh_object(f"repos/{seed_repo}/compare/{basehead}", jq)
    except (LookupError, RuntimeError, ValueError):
        return fork, None
    return fork, res


def process_seed(spec):
    """Rastrea un seed completo y devuelve su bloque de estado."""
    seed_repo, forced_branch = parse_seed(spec)
    meta = gh_object(
        f"repos/{seed_repo}",
        "{pushed_at:.pushed_at, default_branch:.default_branch, "
        "forks:.forks_count, stars:.stargazers_count, archived:.archived}",
    )
    seed_branch = forced_branch or meta["default_branch"]
    seed_owner = seed_repo.split("/")[0]
    seed_pushed = meta["pushed_at"] or "1970-01-01T00:00:00Z"

    try:
        forks = gh_ndjson(
            f"repos/{seed_repo}/forks?sort=newest&per_page=100",
            ".[] | {full_name, pushed_at, stargazers_count, default_branch}",
        )
    except (LookupError, RuntimeError):
        forks = []

    # Filtro barato: solo comparamos forks con push posterior al del seed.
    # Las fechas ISO-8601 UTC ('...Z') se ordenan correctamente como texto.
    candidates = [
        f for f in forks
        if f.get("pushed_at") and f["pushed_at"] > seed_pushed
    ]

    ahead_forks = {}
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = [
            pool.submit(compare_fork, seed_repo, seed_owner, seed_branch, f)
            for f in candidates
        ]
        for fut in futures:
            fork, res = fut.result()
            if not res or (res.get("ahead") or 0) <= 0:
                continue
            ahead_forks[fork["full_name"]] = {
                "ahead": res["ahead"],
                "behind": res["behind"],
                "status": res["status"],
                "pushed_at": fork["pushed_at"],
                "stars": fork.get("stargazers_count", 0),
                "branch": fork.get("default_branch"),
                "commits": res["commits"][:MAX_COMMITS],
            }

    return {
        "repo": seed_repo,
        "branch": seed_branch,
        "pushed_at": seed_pushed,
        "stars": meta.get("stars", 0),
        "archived": meta.get("archived", False),
        "forks_total": meta.get("forks", 0),
        "active_candidates": len(candidates),
        "ahead_forks": ahead_forks,
    }


# --------------------------------------------------------------------------- #
# Delta entre snapshots
# --------------------------------------------------------------------------- #
def compute_delta(old, new):
    """Compara dos snapshots y devuelve novedades por seed."""
    deltas = {}
    old_seeds = (old or {}).get("seeds", {})
    for seed, data in new["seeds"].items():
        old_ahead = old_seeds.get(seed, {}).get("ahead_forks", {})
        new_forks, grown = [], []
        for fork, info in data["ahead_forks"].items():
            if fork not in old_ahead:
                new_forks.append((fork, info))
            elif info["ahead"] != old_ahead[fork].get("ahead"):
                grown.append((fork, old_ahead[fork].get("ahead"), info["ahead"], info))
        if new_forks or grown:
            deltas[seed] = {"new": new_forks, "grown": grown}
    return deltas


# --------------------------------------------------------------------------- #
# Informe Markdown
# --------------------------------------------------------------------------- #
def render_report(state, delta, generated_at):
    L = []
    L.append("# Ecosistema de forks de MacDown")
    L.append("")
    L.append(f"_Generado automáticamente por `claude_tools/track_forks.py` el "
             f"{generated_at}._")
    L.append("")
    L.append("Este informe rastrea, para cada repo semilla (el MacDown original "
             "y las líneas evolucionadas), qué forks tienen commits propios y qué "
             "aportan. Regenéralo con `./claude_tools/track_forks.sh`.")
    L.append("")

    # --- Novedades ---
    L.append("## 🔔 Novedades desde la última ejecución")
    L.append("")
    if not delta:
        L.append("_Sin cambios respecto al snapshot anterior (o primera ejecución)._")
    else:
        for seed, d in delta.items():
            L.append(f"### {seed}")
            for fork, info in d["new"]:
                L.append(f"- 🆕 **{fork}** — ahead {info['ahead']} "
                         f"(⭐{info['stars']}, push {info['pushed_at'][:10]})")
            for fork, old_a, new_a, info in d["grown"]:
                L.append(f"- ⬆️ **{fork}** — {old_a} → {new_a} commits ahead")
            L.append("")
    L.append("")

    # --- Resumen por seed ---
    L.append("## Resumen por seed")
    L.append("")
    L.append("| Seed | Rama | Último push | Forks totales | Activos | Con commits propios |")
    L.append("|---|---|---|---:|---:|---:|")
    for seed, data in state["seeds"].items():
        L.append(
            f"| `{data['repo']}` | {data['branch']} | {data['pushed_at'][:10]} "
            f"| {data['forks_total']} | {data['active_candidates']} "
            f"| {len(data['ahead_forks'])} |"
        )
    L.append("")

    # --- Detalle por seed ---
    for seed, data in state["seeds"].items():
        L.append(f"## {data['repo']}")
        L.append("")
        flag = " · 📦 archivado" if data.get("archived") else ""
        L.append(f"Rama `{data['branch']}` · último push {data['pushed_at'][:10]} "
                 f"· ⭐{data['stars']} · {data['forks_total']} forks{flag}")
        L.append("")
        ahead = data["ahead_forks"]
        if not ahead:
            L.append("_Ningún fork con commits propios detectado._")
            L.append("")
            continue
        ordered = sorted(ahead.items(), key=lambda kv: kv[1]["ahead"], reverse=True)
        for fork, info in ordered:
            L.append(f"### {fork} — ahead {info['ahead']}, behind {info['behind']} "
                     f"(⭐{info['stars']}, push {info['pushed_at'][:10]})")
            for msg in info["commits"]:
                L.append(f"- {msg}")
            L.append("")

    return "\n".join(L) + "\n"


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Rastrea forks de MacDown.")
    ap.add_argument("--seeds", default=DEFAULT_SEEDS)
    ap.add_argument("--state", default=DEFAULT_STATE)
    ap.add_argument("--report", default=DEFAULT_REPORT)
    ap.add_argument("--dry-run", action="store_true",
                    help="No escribe FORKS.md ni el snapshot; solo imprime un resumen.")
    args = ap.parse_args()

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    seeds = load_seeds(args.seeds)
    print(f"Rastreando {len(seeds)} seeds…", file=sys.stderr)

    state = {"generated_at": generated_at, "seeds": {}}
    for spec in seeds:
        repo = parse_seed(spec)[0]
        print(f"  · {repo}", file=sys.stderr, flush=True)
        try:
            state["seeds"][repo] = process_seed(spec)
        except Exception as exc:  # noqa: BLE001 — un seed roto no debe tumbar todo
            print(f"    ⚠️  fallo en {repo}: {exc}", file=sys.stderr)
            state["seeds"][repo] = {
                "repo": repo, "branch": "?", "pushed_at": "1970-01-01T00:00:00Z",
                "stars": 0, "archived": False, "forks_total": 0,
                "active_candidates": 0, "ahead_forks": {}, "error": str(exc),
            }

    old = None
    if os.path.exists(args.state):
        try:
            with open(args.state) as fh:
                old = json.load(fh)
        except (OSError, ValueError):
            old = None
    # Sin snapshot previo => baseline: no hay "novedades" que reportar todavía.
    delta = compute_delta(old, state) if old is not None else {}

    # Resumen a stderr
    total_ahead = sum(len(s["ahead_forks"]) for s in state["seeds"].values())
    print(f"\nForks con commits propios: {total_ahead}", file=sys.stderr)
    if delta:
        n_new = sum(len(d["new"]) for d in delta.values())
        n_grown = sum(len(d["grown"]) for d in delta.values())
        print(f"Novedades: {n_new} forks nuevos, {n_grown} con commits nuevos.",
              file=sys.stderr)

    if args.dry_run:
        print("(dry-run: no se escribe nada)", file=sys.stderr)
        return

    os.makedirs(os.path.dirname(args.report), exist_ok=True)
    with open(args.report, "w") as fh:
        fh.write(render_report(state, delta, generated_at))
    with open(args.state, "w") as fh:
        json.dump(state, fh, indent=2, ensure_ascii=False)
    print(f"Escrito {args.report}", file=sys.stderr)
    print(f"Escrito {args.state}", file=sys.stderr)


if __name__ == "__main__":
    main()
