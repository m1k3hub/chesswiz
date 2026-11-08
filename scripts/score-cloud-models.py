#!/usr/bin/env python3
"""Score cloud models on the assistant corpus and write ai-models.json.

The app (::ai::provider::resolveFrontier) reads the published file, keeps
the five most capable models (best score, then lowest cost) and, on the
first start, uses the one the user can reach with the least setup (setup:
1 easiest), then the cheapest. Run from the repo root with a built
src/tkchesswiz, a local Ollama signed in to its cloud, and the keys of the
other providers in the environment (a provider without a key is skipped):

    SCIDB_CORPUS_DB=<a .sci database> scripts/score-cloud-models.py \
        [--jobs 2] [--per-provider 4] [--only PROVIDER,...]

Prices are OpenRouter's (USD per token); a request is costed at
REQUEST_TOKENS input and output tokens (the assistant sends its tools with
every request, so input dominates). Logs and reports go to
tests/tmp-app/model-scores/; scores already in --out are kept for models
not run again. Publish with
    aws --profile chesswiz s3 cp tests/tmp-app/model-scores/ai-models.json \
        s3://chesswizapp-media/ai/ai-models.json --content-type application/json
"""
import argparse, concurrent.futures, datetime, json, os, re, subprocess, sys, tempfile, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OLLAMA = "http://localhost:11434"
REQUEST_TOKENS = {"in": 6000, "out": 250}

# How hard each provider is to set up, 1 easiest: Ollama needs only a free
# sign-in, Gemini a free key from a Google account, the rest a paid key.
SETUP = {"ollama": 1, "gemini": 2, "fireworks": 3, "qwen": 3, "anthropic": 3, "openai": 3}
KEYS = {"gemini": ["GEMINI_API_KEY", "GOOGLE_API_KEY"], "fireworks": ["FIREWORKS_API_KEY"],
        "qwen": ["QWEN_TOKEN_PLAN_API_KEY", "QWEN_API_KEY"], "anthropic": ["ANTHROPIC_API_KEY"],
        "openai": ["OPENAI_API_KEY"]}
LISTS = {"gemini": "https://generativelanguage.googleapis.com/v1beta/openai/models",
         "fireworks": "https://api.fireworks.ai/inference/v1/models",
         "qwen": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/models",
         "openai": "https://api.openai.com/v1/models"}
# when a provider lists nothing: the app's default for it (tcl/ai-provider.tcl)
DEFAULTS = {"fireworks": ["accounts/fireworks/models/glm-5p3"], "anthropic": ["claude-haiku-5-5", "claude-sonnet-5-5"]}
NOT_CHAT = re.compile(r"tts|audio|image|embed|realtime|vision-exp|veo|imagen|wan\d|live|aqa|robotics|lyria|^auto$")


def get(url, body=None, timeout=60, key=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = "Bearer " + key
    with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers), timeout=timeout) as r:
        return json.load(r)


def key_of(provider):
    return next((os.environ[v] for v in KEYS.get(provider, []) if os.environ.get(v)), "")


def norm(name):
    name = name.split("/")[-1].lower()
    name = re.sub(r"(-cloud|:cloud)$", "", name)
    name = re.sub(r"(\d)p(\d)", r"\1\2", name)  # Fireworks: glm-5p3 = glm-5.3
    return re.sub(r"[^a-z0-9]", "", name)


def prices():
    """normalized model name -> cost of one request in USD (OpenRouter)."""
    out = {}
    for m in get("https://openrouter.ai/api/v1/models")["data"]:
        if ":" in m["id"]:
            continue  # :free, :batch variants
        p = m["pricing"]
        cost = float(p["prompt"]) * REQUEST_TOKENS["in"] + float(p["completion"]) * REQUEST_TOKENS["out"]
        if cost > 0:  # routers carry negative placeholders, free tiers 0
            out.setdefault(norm(m["id"]), cost)
    return out


def price_for(model, table):
    n = norm(model)
    if n in table:
        return table[n]
    for k in (n + "it", n + "instruct"):
        if k in table:
            return table[k]
    return None


def cloud_tag(name):
    return name + "-cloud" if ":" in name else name + ":cloud"


def ollama_candidates():
    # sorted: the catalogue order changes between calls, and --part needs a stable list
    tags = sorted(cloud_tag(m["name"]) for m in get("https://ollama.com/api/tags")["models"])
    good = []
    for t in tags:
        try:
            get(OLLAMA + "/api/pull", {"model": t, "stream": False}, timeout=120)
            if "tools" in get(OLLAMA + "/api/show", {"model": t}).get("capabilities", []):
                good.append(t)
        except Exception:
            pass
    return good


def provider_candidates(provider):
    key = key_of(provider)
    if not key:
        return []
    names = []
    if provider in LISTS:
        try:
            names = [m["id"].removeprefix("models/") for m in get(LISTS[provider], key=key).get("data", [])]
        except Exception:
            names = []
    names = [n for n in names if not NOT_CHAT.search(n)]
    return names or DEFAULTS.get(provider, [])


def score(provider, model, workdir, app):
    home = tempfile.mkdtemp(dir=workdir)
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", f"{provider}-{model}")
    env = dict(os.environ, HOME=home, SCIDB_USERDIR=home + "/.chesswiz", PULSE_SINK="cwtests",
               CHESSWIZ_NO_FRONTIER="1", CHESSWIZ_NO_SETUP_SCAN="1",
               SCIDB_AI_PROVIDER=provider, SCIDB_AI_MODEL=model,
               SCIDB_CORPUS_REPORT=os.path.join(workdir, safe + ".txt"))
    log = os.path.join(workdir, safe + ".log")
    # no X server to fake on macOS: the app runs in the console session
    cmd = (["xvfb-run", "-a"] if sys.platform.startswith("linux") else []) + [app, "tests/run_assistant_corpus.tcl"]
    with open(log, "w") as f:
        try:
            subprocess.run(cmd, cwd=ROOT, env=env, stdout=f, stderr=subprocess.STDOUT, timeout=5400)
        except subprocess.TimeoutExpired:
            pass
    m = re.search(r"SOLVED (\d+)/(\d+) \(\d+%\).*?, ([\d.]+)s a request", open(log).read())
    if not m or int(m.group(2)) == 0:
        return None
    good, total, seconds = int(m.group(1)), int(m.group(2)), float(m.group(3))
    return {"solved": good, "total": total, "score": round(100.0 * good / total, 1), "seconds": seconds}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--per-provider", type=int, default=4, help="cheapest models scored per keyed provider")
    ap.add_argument("--only", default="", help="providers to score, comma-separated")
    ap.add_argument("--part", default="1/1", help="K/N: score every Nth model from the Kth, to split a run over machines")
    ap.add_argument("--exclude", default="", help="models not to score, comma-separated")
    ap.add_argument("--app", default="src/tkchesswiz", help="the tkchesswiz binary")
    ap.add_argument("--out", default=os.path.join(ROOT, "tests/tmp-app/model-scores/ai-models.json"))
    a = ap.parse_args()
    part, parts = map(int, a.part.split("/"))
    if not os.path.exists(os.environ.get("SCIDB_CORPUS_DB", "")):
        raise SystemExit("set SCIDB_CORPUS_DB to a .sci database")
    workdir = os.path.join(ROOT, "tests/tmp-app/model-scores")
    os.makedirs(workdir, exist_ok=True)

    table = prices()
    providers = a.only.split(",") if a.only else list(SETUP)
    jobs = []
    for provider in providers:
        if provider == "ollama":
            names = ollama_candidates()
        else:
            names = provider_candidates(provider)
            # the cheapest priced ones; unpriced models are not candidates
            priced = sorted((price_for(n, table), n) for n in names if price_for(n, table) is not None)
            names = [n for _, n in priced[:a.per_provider]]
        jobs += [(provider, n) for n in names]
    jobs = [j for j in jobs if j[1] not in a.exclude.split(",")][part - 1::parts]
    print(f"scoring {len(jobs)} models:", ", ".join(f"{p}/{m}" for p, m in jobs), flush=True)

    old = {}
    if os.path.exists(a.out):
        old = {(m["provider"], m["model"]): m for m in json.load(open(a.out))["models"]}
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as pool:
        for (provider, model), result in zip(jobs, pool.map(lambda j: score(*j, workdir, a.app), jobs)):
            print(f"{provider}/{model}: {result}", flush=True)
            if result:
                old[(provider, model)] = dict(provider=provider, model=model, cost=price_for(model, table),
                                              scored=str(datetime.date.today()), **result)

    out = {"updated": str(datetime.date.today()), "setup": SETUP,
           "request_tokens": REQUEST_TOKENS, "prices": "openrouter.ai, USD per request",
           "corpus": "tests/assistant_corpus.tcl",
           "models": sorted(old.values(), key=lambda m: (SETUP.get(m["provider"], 99), m["cost"] if m["cost"] is not None else 1e30))}
    json.dump(out, open(a.out, "w"), indent=1)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
