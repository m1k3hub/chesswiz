import json, re, sys, collections

rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
by = {r["id"]: r for r in rows}
TOPS = {"01": "File", "02": "Edit", "03": "Game", "04": "Database", "05": "Board",
        "06": "Analysis", "07": "Training", "08": "Tools", "09": "View", "10": "Help"}
CTX = {
    "C1": "Board square / position (right-click the board)",
    "C2": "A move in the notation",
    "C3": "A game row in the game list",
    "C4": "A database in the database switcher",
    "C5": "A player, event or site (tables and cards)",
    "C6": "An engine line in the analysis pane",
    "C7": "A media entry",
    "C8": "A row in the opening tree",
    "C9": "A pane header (each pane's own menu)",
    "C10": "A table column header",
    "C11": "A comment in the comment editor",
    "C12": "The game bar (a game tab)",
}


def cell(s):
    s = re.sub(r"\s+", " ", s or "").strip()
    return s.replace("|", "\\|")


def label(r):
    l = r.get("shown") or r.get("label") or r["id"]
    l = l.replace("&", "") if re.search(r"&\w", l) else l
    return cell(l)


def how(r):
    parts = []
    p = (r.get("purpose") or "").strip()
    w = (r.get("when") or "").strip()
    d = (r.get("doc") or "").strip()
    if p:
        parts.append(p)
    elif d and d.rstrip("…. ") != (r.get("label") or "").rstrip("…. "):
        parts.append(d)
    elif r.get("what") and r.get("what") != r.get("label"):
        parts.append(r["what"][0].upper() + r["what"][1:] + ".")
    if w:
        parts.append(w)
    if r.get("confirm") in ("1", "true"):
        parts.append("Asks for confirmation first.")
    return cell(" ".join(parts)) or "—"


def key(r):
    k = (r.get("keys") or "").split(" ", 1)
    if len(k) > 1 and k[1].strip() not in ("", "{}"):
        return cell(k[1].strip("{} "))
    return ""


def menupath(r):
    if (r.get("dropdown") or "").startswith("00."):
        if r["id"].startswith("menu.help.donate"):
            return "♥ Donate button (top strip) ▸ " + label(r)
        return label(r) + " — *not placed in any menu*"
    if r.get("path"):
        return cell(r["path"].replace(" > ", " ▸ "))
    top = TOPS.get((r.get("dropdown") or "").split(".")[0], "")
    segs = r["id"].split(".")[2:-1] if r["id"].startswith("menu.") else []
    mid = [s.replace("_", " ").title() for s in segs]
    return cell(" ▸ ".join([top] + mid + [label(r)]))


def surfaces(r):
    s = []
    if r.get("dropdown"): s.append("menu")
    if r.get("context"): s.append("context")
    if key(r): s.append("key")
    if re.match(r"toolbar\.", r["id"]): s.append("toolbar")
    if re.match(r"td\.", r["id"]): s.append("td")
    if re.match(r"command\.", r["id"]): s.append("command")
    return s


out = []
w = out.append
n = collections.Counter()
for r in rows:
    for s in surfaces(r): n[s] += 1
    n["ai:" + (r.get("ai") or "0")] += 1

w("# Chesswiz feature catalog\n")
w("Generated on 2026-11-27 from the live action registry (`::action::Registry`, "
  f"{len(rows)} actions) of master, with descriptions from the registry and from "
  "`tcl/knowledge.tcl`. Regenerate it rather than editing the catalog by hand; the "
  "findings in section 2 are written by hand.\n")

w("## 1. How features are reached\n")
w("Every user-visible operation is a registered action. One feature can have several "
  "entries, one per place you reach it (the main menu, a right-click menu, a toolbar, "
  "a key, the Ask field, the assistant).\n")
w("| Surface | Actions | How you use it |\n|---|---|---|")
w(f"| Main menu | {n['menu']} | **Main Menu** button, top right. Ten menus: File, Edit, Game, Database, Board, Analysis, Training, Tools, View, Help. |")
w(f"| Right-click menus | {n['context']} | Twelve context menus (C1–C12), section 3.3. Each starts with *What can I do here?*, which asks the assistant about that object. |")
w(f"| Keyboard shortcuts | {n['key']} | Listed per entry; all are rebindable under Edit ▸ Keyboard Preferences…. |")
w(f"| Toolbars | {n['toolbar']} | Pane toolbars (board, notation, analysis, tree, database switcher, …). |")
w(f"| Tournament Director | {n['td']} | Tools ▸ Tournament Director… workspace. |")
w(f"| Typed commands | {n['command']} | Type in the Ask field (Ctrl+K): *open database …*, *find games …*, *play engine* … |")
w(f"| Assistant tools | {n['ai:1']} | Used by the AI assistant when you ask in plain language. Those that need no arguments also appear as suggestions in the Ask field. |")
w(f"| Developer tools | {n['ai:debug']} | Only with `--ai-debug` or `SCIDB_AI_DEBUG=1`. |")
w("")
w("The Ask field (top right, Ctrl+K) searches every runnable action by name and description, so anything in this catalog that needs no arguments can also be started by typing its name.\n")

w("## 2. Findings\n")
w(open(sys.argv[2], encoding="utf-8").read())

w("## 3. Catalog\n")
w("Each row: where to find it, its shortcut, and what it does.\n")

w("### 3.1 Main menu\n")
menu = sorted([r for r in rows if r.get("dropdown")], key=lambda r: [int(x) for x in r["dropdown"].split(".")])
cur = None
for r in menu:
    top = TOPS.get(r["dropdown"].split(".")[0], "Donate button (top strip)")
    if top != cur:
        cur = top
        w(f"\n#### {top}\n\n| Menu path | Key | How it works |\n|---|---|---|")
    w(f"| {menupath(r)} | {key(r)} | {how(r)} |")
w("")

keyonly = [r for r in rows if key(r) and not r.get("dropdown") and not r.get("context")]
if keyonly:
    w("### 3.2 Keyboard-only actions\n\n| Action | Key | How it works |\n|---|---|---|")
    for r in sorted(keyonly, key=lambda r: label(r)):
        w(f"| {label(r)} | {key(r)} | {how(r)} |")
    w("")

w("### 3.3 Right-click menus\n")
for cid in [f"C{i}" for i in range(1, 13)]:
    items = [r for r in rows if cid in (r.get("context") or "").split() and r["id"] != "context.ask"]
    items = [r for r in items if r["id"].lower().startswith(cid.lower() + ".")] or items
    w(f"\n#### {cid}: {CTX[cid]}\n\n| Entry | Key | How it works |\n|---|---|---|")
    for r in sorted(items, key=lambda r: r["id"]):
        w(f"| {label(r)} | {key(r)} | {how(r)} |")
w("")

w("### 3.4 Toolbars\n")
tb = collections.defaultdict(list)
for r in rows:
    m = re.match(r"toolbar\.([^.]+)\.", r["id"])
    if m: tb[m.group(1)].append(r)
for name in sorted(tb):
    w(f"\n#### {name.replace('_', ' ').title()}\n\n| Button | How it works |\n|---|---|")
    for r in sorted(tb[name], key=lambda r: int(r["id"].rsplit(".", 1)[1]) if r["id"].rsplit(".", 1)[1].isdigit() else 0):
        w(f"| {label(r)} | {how(r)} |")
w("")

w("### 3.5 Tournament Director\n\nOpen with Tools ▸ Tournament Director…. Entries marked *assistant only* have no button in the workspace.\n\n| Operation | In the workspace | How it works |\n|---|---|---|")
tdui = open(sys.argv[3], encoding="latin-1").read()
for r in sorted([r for r in rows if r["id"].startswith("td.")], key=lambda r: r["id"]):
    shown = {"td.standings": "Standings tab", "td.crosstable": "Standings tab ▸ Crosstable",
             "td.status": "Event tab (status lines)", "td.workspace": "Tools ▸ Tournament Director…"}
    inui = shown.get(r["id"]) or ("yes" if re.search(re.escape(r["id"]) + r"\b", tdui) else "*assistant only*")
    w(f"| {label(r)} | {inui} | {how(r)} |")
w("")

w("### 3.6 Typed commands (Ask field)\n\n| Command | How it works |\n|---|---|")
for r in sorted([r for r in rows if r["id"].startswith("command.")], key=lambda r: r["id"]):
    w(f"| {label(r)} | {how(r)} |")
w("")

w("### 3.7 Assistant tools\n\nThe assistant calls these when you ask for something in plain language (Tools ▸ Assistant, or *Ask a question* in the Ask field). *Elsewhere* names the menu or button for the same feature where one exists.\n")
w("| Tool | Elsewhere | How it works |\n|---|---|---|")
equiv = json.load(open(sys.argv[4], encoding="utf-8"))
for r in sorted([r for r in rows if r.get("ai") == "1" and not surfaces(r)], key=lambda r: r["id"]):
    w(f"| `{r['id']}` | {cell(equiv.get(r['id'], '—'))} | {how(r)} |")
w("")

w("### 3.8 Developer tools (debug mode only)\n\n| Tool | How it works |\n|---|---|")
for r in sorted([r for r in rows if r.get("ai") == "debug"], key=lambda r: r["id"]):
    w(f"| `{r['id']}` | {how(r)} |")
w("")

w("### 3.9 Controls the assistant can operate\n\nThese mirror controls inside panes and dialogs (the control itself is how you use them; the action lets the assistant and the Ask field operate it).\n\n| Control | How it works |\n|---|---|")
for r in sorted([r for r in rows if r.get("ai") == "0" and not surfaces(r) and not r["id"].startswith(("menu.", "c", "context."))], key=lambda r: r["id"]):
    w(f"| {label(r)} (`{r['id']}`) | {how(r)} |")
w("")

open(sys.argv[5], "w", encoding="utf-8").write("\n".join(out) + "\n")
print(len(out), "lines")
