#!/usr/bin/env python3
"""checks/frontier.py — which steps of an issue's lifecycle are realized, and
which are ready: a pure function over the graph in checks/lifecycle.mk, the
issue's ledger and the current hashes. It records nothing; reading rebuilds
the local cache (checks/state.sh local), and the diff's hash comes from
checks/workflow.sh diff-sha <issue>.

  frontier.py <issue>      reads the local ledger (checks/state.sh local: this
                           machine's journal only, never the issue's comments), hashes the
                           diff of the issue's tree (checks/workflow.sh
                           diff-sha <issue>), prints
                           `realized <step>`, `ready <step> <entry> <rule>` and
                           `deferred <step>`; exit 0, or 2 when it cannot read
  frontier.py              self-test

A step is ready when it is not realized and every step it rests on is.
The rules (see checks/lifecycle.mk): present, facts, diff, declared:facts,
declared:diff. Facts are the Belnap table rows of 15_facts,
`| ID | Proposition | Status | Evidence | DependsOn |`; the latest row for an
ID is its current one, and an ESTABLISHED fact resting on a RETRACTED,
UNKNOWN or CONTRADICTED one counts as UNKNOWN (the retraction cascade).
"""
import hashlib
import os
import re
import subprocess
import sys

STATUSES = {"ESTABLISHED", "CONTRADICTED", "UNKNOWN", "RETRACTED"}


RULES = re.compile(r"^(present|facts|diff|declared:(facts|diff))$")


def parse_graph(text):
    """(steps, edges): steps maps a step to (entry, rule), edges a step to its
    prerequisites (a target on several rule lines rests on all of them). Fails
    closed: a line outside the grammar, a `#:` line it cannot read or a second
    one for a step, an unknown rule, an edge naming a step with no `#:` line, a
    cycle, a missing finish, or a step finish does not reach raises ValueError."""
    steps, edges = {}, {}
    for n, line in enumerate(text.split("\n"), 1):
        # the grammar: comments, blank lines, tab-indented recipes, and rules
        # `<step>: <step>...` from column 0; anything else is an error
        if line.startswith("#:"):
            m = re.match(r"#:\s+(\S+)\s+(\S+)\s+(\S+)\s*$", line)
            if not m or not RULES.match(m.group(3)):
                raise ValueError("line %d: not `#: <step> <entry> <rule>`: %s" % (n, line))
            if m.group(1) in steps:
                raise ValueError("line %d: a second `#:` line for %s" % (n, m.group(1)))
            steps[m.group(1)] = (m.group(2), m.group(3))
            continue
        if line.startswith("\t") and line.strip().startswith("#:"):
            raise ValueError("line %d: a `#:` line must start in column 0" % n)
        if line.startswith("\t") and not edges:
            raise ValueError("line %d: a recipe before any rule" % n)
        if line.startswith(("#", "\t")) or not line.strip():
            continue
        m = re.match(r"([a-z][a-z0-9-]*):((?:[ \t]+[a-z][a-z0-9-]*)*)[ \t]*$", line)
        if not m:
            raise ValueError("line %d: not a rule `<step>: <step>...` from column 0, a comment or a recipe: %r" % (n, line))
        edges.setdefault(m.group(1), []).extend(m.group(2).split())
    for t, ps in edges.items():
        if "finish" in ps:
            raise ValueError("finish is the last target; %s cannot rest on it" % t)
        for x in [t] + ps:
            if x != "finish" and x not in steps:
                raise ValueError("step %s has no `#:` line" % x)
    for st in steps:
        if st not in edges:
            raise ValueError("step %s has a `#:` line but no rule" % st)
    # a cycle is an error of the graph, whatever the ledger holds
    state = {}

    def visit(x, path):
        if state.get(x) == "done":
            return
        if x in path:
            raise ValueError("the graph has a cycle: %s" % " -> ".join(path[path.index(x):] + (x,)))
        for y in edges.get(x, []):
            visit(y, path + (x,))
        state[x] = "done"

    for x in edges:
        visit(x, ())
    if "finish" not in edges:
        raise ValueError("the graph has no finish target")
    reach, todo = set(), ["finish"]
    while todo:
        x = todo.pop()
        if x not in reach:
            reach.add(x)
            todo.extend(edges.get(x, []))
    lost = [st for st in steps if st not in reach]
    if lost:
        raise ValueError("finish does not reach %s" % ", ".join(lost))
    if any(r.startswith("declared:facts") for _, r in steps.values()) and \
            sum(1 for _, r in steps.values() if r == "facts") != 1:
        raise ValueError("a declared:facts step needs exactly one facts step to bind to")
    return steps, edges


def field(text, name):
    """The value of header `name:` in the entry's leading header block (the
    `Name: value` lines, names capitalized, before the first other line), or
    None. A header given twice in the block is None: which one holds is not
    clear, so nothing is realized by it. Lines after the block do not count."""
    vals = []
    for line in (text or "").split("\n"):
        m = re.match(r"([A-Z][A-Za-z0-9-]*):[ \t]*(.*?)[ \t]*$", line)
        if not m:
            break
        if m.group(1) == name:
            vals.append(m.group(2))
    return vals[0] if len(vals) == 1 else None


def facts(text):
    """(problems, table): the current row per fact ID, after the cascade."""
    rows, bad, problems = {}, {}, []
    # the latest row for an ID is the fact; only it is judged
    for line in (text or "").split("\n"):
        if not line.strip().startswith("|"):
            # a table row without its leading pipe would hide a fact; entry
            # headers never hold a pipe, so any line with one must be a row
            if "|" in line:
                problems.append("a table row must start with |: %s" % line.strip())
            continue
        # a cell may hold a pipe written \|; only an unescaped pipe at either end bounds the row
        row = re.sub(r"^\|", "", line.strip())
        row = re.sub(r"(?<!\\)\|$", "", row)
        cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", row)]
        # the exact header row and the separator row (every cell dashes) are
        # the table's frame; a fact row needs a proper ID; anything else is reported
        if cells == ["ID", "Proposition", "Status", "Evidence", "DependsOn"] or all(re.match(r"^:?-+:?$", c) for c in cells):
            continue
        fid = cells[0]
        if not re.match(r"^[A-Za-z][A-Za-z0-9_.-]*$", fid):
            problems.append("a row without a proper ID (a letter, then letters, digits, . _ -): %s" % line.strip())
            continue
        bad.pop(fid, None)
        if len(cells) != 5:
            bad[fid] = "%s: a row needs 5 cells (ID, Proposition, Status, Evidence, DependsOn), has %d" % (fid, len(cells))
            rows.pop(fid, None)
            continue
        _, _, status, _, deps = cells
        if status not in STATUSES:
            bad[fid] = "%s: status %r is not one of %s" % (fid, status, "/".join(sorted(STATUSES)))
        rows[fid] = {"status": status, "deps": [d.strip() for d in deps.split(",") if d.strip() and d.strip() != "-"]}
    problems += [bad[f] for f in sorted(bad)]

    # the cascade, depth-first with an explicit stack, so a chain's length is no
    # limit: a fact counts as UNKNOWN when one it rests on is RETRACTED, UNKNOWN,
    # CONTRADICTED, missing, or on a cycle with it
    eff, state = {}, {}
    for root in rows:
        if root in eff:
            continue
        state[root] = 1
        stack = [(root, 0)]
        while stack:
            fid, i = stack[-1]
            deps = rows[fid]["deps"] if rows[fid]["status"] == "ESTABLISHED" else []
            if i < len(deps):
                stack[-1] = (fid, i + 1)
                d = deps[i]
                if d in rows and d not in state:
                    state[d] = 1
                    stack.append((d, 0))
                continue
            out = rows[fid]["status"]
            if out == "ESTABLISHED" and any(eff.get(d, "UNKNOWN") in ("RETRACTED", "UNKNOWN", "CONTRADICTED") for d in deps):
                out = "UNKNOWN"
            eff[fid] = out
            stack.pop()
    problems += ["%s: CONTRADICTED" % f for f, s in sorted(eff.items()) if s == "CONTRADICTED"]
    problems += ["%s: rests on %s" % (f, ",".join(rows[f]["deps"])) for f in sorted(rows)
                 if rows[f]["status"] == "ESTABLISHED" and eff[f] == "UNKNOWN"]
    if not rows and not bad:
        problems.append("no facts recorded")
    return problems, eff


def realized(rule, entry_text, current):
    """Whether an entry with entry_text realizes its step under rule, given current {'diff', 'facts'}."""
    if entry_text is None:
        return False
    if rule == "present":
        return True
    if rule == "facts":
        return not facts(entry_text)[0]
    # a hash missing on either side never matches
    if rule == "diff":
        have = field(entry_text, "Diff-Sha")
        return bool(have) and bool(current.get("diff")) and have == current["diff"]
    if rule.startswith("declared:"):
        bound = rule.split(":", 1)[1]
        key = {"diff": "Diff-Sha", "facts": "Facts-Sha"}[bound]
        have = field(entry_text, key)
        return field(entry_text, "Declared-By") == "operator" and bool(have) and bool(current.get(bound)) and have == current[bound]
    raise ValueError("unknown rule " + rule)


def frontier(steps, edges, ledger, current):
    """{'realized': [...], 'ready': [...], 'deferred': [...]} in graph order."""
    # a step is realized when its own rule holds and every step it rests on is
    # realized, so a broken fact or a stale plan undoes everything above it
    memo = {}

    def done(s, path=()):
        if s in memo:
            return memo[s]
        if s in path:
            raise ValueError("the graph has a cycle through " + s)
        entry, rule = steps[s]
        memo[s] = realized(rule, ledger.get(entry), current) and all(done(p, path + (s,)) for p in edges.get(s, []))
        return memo[s]

    out = {"realized": [], "ready": [], "deferred": []}
    for s in steps:
        if done(s):
            out["realized"].append(s)
        elif all(done(p) for p in edges.get(s, [])):
            out["ready"].append(s)
        else:
            out["deferred"].append(s)
    return out


def sha(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


def main(issue):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", issue):
        print("frontier: %r is not an issue id" % issue, file=sys.stderr)
        return 2
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    run = lambda *a: subprocess.run(a, cwd=root, capture_output=True, text=True)
    p = run("checks/state.sh", "local", issue)
    if p.returncode != 0 or not p.stdout.strip():
        print("frontier: checks/state.sh local %s failed: %s" % (issue, p.stderr.strip()), file=sys.stderr)
        return 2
    try:
        steps, edges = parse_graph(open(os.path.join(root, "checks/lifecycle.mk")).read())
    except ValueError as e:
        print("frontier: checks/lifecycle.mk: %s" % e, file=sys.stderr)
        return 2
    d = p.stdout.strip()
    raw = {f[:-3]: open(os.path.join(d, f), "rb").read() for f in os.listdir(d) if f.endswith(".md")}
    ledger = {k: v.decode("utf-8", "replace") for k, v in raw.items()}
    # the issue's own tree, which need not be this checkout
    q = run("checks/workflow.sh", "diff-sha", issue)
    # exit 3: no change yet; exit 4: the issue has no tree yet. Either way no
    # diff-bound step can be realized, and the plan steps still show
    if q.returncode not in (0, 3, 4) or (q.returncode == 0 and not q.stdout.strip()):
        print("frontier: checks/workflow.sh diff-sha failed: %s" % q.stderr.strip(), file=sys.stderr)
        return 2
    # the entry the graph's facts step names, as raw bytes, as declare hashes it
    fe = [e for e, r in steps.values() if r == "facts"]
    current = {"diff": q.stdout.strip() if q.returncode == 0 else None,
               "facts": sha(raw[fe[0]]) if len(fe) == 1 and fe[0] in raw else None}
    try:
        out = frontier(steps, edges, ledger, current)
    except ValueError as e:
        print("frontier: %s" % e, file=sys.stderr)
        return 2
    for s in out["realized"]:
        print("realized", s)
    for s in out["ready"]:
        entry, rule = steps[s]
        why = ""
        if rule == "facts" and entry in ledger:
            why = " (" + "; ".join(facts(ledger[entry])[0]) + ")"
        print("ready %s %s %s%s" % (s, entry, rule, why))
    for s in out["deferred"]:
        print("deferred", s)
    return 0


def selftest():
    fail = 0

    def check(name, ok):
        nonlocal fail
        print(("ok   " if ok else "FAIL ") + name)
        fail |= not ok

    g = "#: a  10_x present\n#: b  15_f facts\n#: c  20_p declared:facts\n#: d  30_r diff\n" \
        "finish: d\nd: c\n\t@echo d\nc: b\nb: a\na:\n"
    steps, edges = parse_graph(g)
    check("the graph's steps and edges parse", steps["c"] == ("20_p", "declared:facts") and edges["d"] == ["c"])
    cur = {"diff": "D1", "facts": None}
    out = frontier(steps, edges, {}, cur)
    check("an empty ledger: the first step is ready, the rest deferred", out["ready"] == ["a"] and out["deferred"] == ["b", "c", "d"])
    f1 = "| F1 | p | ESTABLISHED | cmd exit 0 | - |\n| F2 | q | UNKNOWN | - | - |\n"
    check("an open UNKNOWN fact does not block the plan", not facts(f1)[0])
    check("a CONTRADICTED fact blocks it", facts(f1 + "| F3 | r | CONTRADICTED | x | - |\n")[0] != [])
    casc = f1 + "| F4 | s | ESTABLISHED | x | F1 |\n| F1 | p | RETRACTED | probe | - |\n"
    probs, eff = facts(casc)
    check("a later row replaces a fact, and its dependents cascade to UNKNOWN", eff["F1"] == "RETRACTED" and eff["F4"] == "UNKNOWN" and any("F4" in p for p in probs))
    check("a status outside the four is a problem", facts("| F1 | p | Established | x | - |\n")[0] != [])
    led = {"10_x": "Branch: b\n", "15_f": f1}
    cur = {"diff": "D1", "facts": sha(f1)}
    check("facts realized, so the plan is ready", frontier(steps, edges, led, cur)["ready"] == ["c"])
    led["20_p"] = "Declared-By: agent\nFacts-Sha: %s\n" % sha(f1)
    check("a declaration not by the operator does not count", "c" in frontier(steps, edges, led, cur)["ready"])
    led["20_p"] = "Declared-By: operator\nFacts-Sha: %s\n" % sha(f1)
    check("the operator's declaration on these facts realizes the plan", frontier(steps, edges, led, cur)["ready"] == ["d"])
    led2 = dict(led, **{"15_f": f1 + "| F5 | t | UNKNOWN | - | - |\n"})
    check("a fact added after the plan makes the plan ready again", "c" in frontier(steps, edges, led2, dict(cur, facts=sha(led2["15_f"])))["ready"])
    led["30_r"] = "Diff-Sha: D1\n"
    check("rows on this diff are realized", "d" in frontier(steps, edges, led, cur)["realized"])
    check("an edit to the diff makes them ready again", "d" in frontier(steps, edges, led, dict(cur, diff="D2"))["ready"])
    check("an entry with no Diff-Sha never matches a missing current hash", not realized("diff", "Rev: x\n", {"diff": None}))
    check("nor does a declaration with no bound hash", not realized("declared:facts", "Declared-By: operator\n", {"facts": None}))
    led3 = dict(led, **{"15_f": f1 + "| F9 | z | CONTRADICTED | x | - |\n"})
    out3 = frontier(steps, edges, led3, dict(cur, facts=sha(led3["15_f"])))
    check("a contradiction undoes every step above the facts", out3["ready"] == ["b"] and out3["realized"] == ["a"])
    for cyc in ("#: a 10_x present\na: a\n", "#: a 10_x present\n#: b 15_f present\na: b\nb: a\n"):
        try:
            parse_graph(cyc); ok = False
        except ValueError:
            ok = True
        check("the graph parser refuses a cycle %r" % cyc.split("\n")[-2], ok)
    s2, e2 = parse_graph("finish: b\n#: a 10_x present\n#: b 15_f present\nb: a\nb:\na:\n")
    check("a target on two lines keeps both lines' prerequisites", e2["b"] == ["a"])
    check("a quoted header in the body does not count", field("Diff-Sha: D1\n\nfinding: Diff-Sha: D2\nDiff-Sha: D3\n", "Diff-Sha") == "D1")
    for bad in ("#: a 10_x present\n#: a 10_x diff\na:\n", "#: a 10_x present\n#: b 15_f present\nb:\n b: a\na:\n", "#: a 10_x present\na: finish\n", "finish: a\n#: a 10_x present\n#: b 15_f present\na:\nb:\n", "#: a 10_x present\na:\n", "#: a 10_x present\n#: b 15_f present\nb : a\na:\n", "#: a 10_x present # note\n", "#: a 10_x maybe\n", "#: a 10_x present\nb: a\n", "#: a 10_x present\n", "#: a 10_x present\na:\nfoo = bar\n"):
        try:
            parse_graph(bad); ok = False
        except ValueError:
            ok = True
        check("the graph parser refuses %r" % bad.split("\n")[0][:30], ok)
    check("a bad row replaced by a good one is not reported", not facts("| F1 | p | Established | x | - |\n| F1 | p | ESTABLISHED | x | - |\n")[0])
    check("a row whose ID is all dashes is not taken for the separator", facts("| - | p | CONTRADICTED | x | - |\n| F1 | q | ESTABLISHED | x | - |\n")[0] != [])
    check("a lowercase line ends the header block", field("Diff-Sha: A\nwarning: Diff-Sha: B\nDiff-Sha: B\n", "Diff-Sha") == "A")
    check("a header given twice in the block is not trusted", field("Diff-Sha: A\nDiff-Sha: B\n", "Diff-Sha") is None)
    check("a row whose first cell is ID is a fact, not the header", facts("| ID | p | CONTRADICTED | x | - |\n| F1 | q | ESTABLISHED | x | - |\n")[0] != [])
    check("the exact header row is the frame", not facts("| ID | Proposition | Status | Evidence | DependsOn |\n|---|---|---|---|---|\n| F1 | q | ESTABLISHED | x | - |\n")[0])
    check("a bare - is not an ID", facts("| - | p | ESTABLISHED | x | - |\n")[0] != [])
    check("only a newline ends a line", facts("| F1 | p | CONTRADICTED | x | - |\x85| F1 | p | ESTABLISHED | x | - |\n")[0] != [])
    check("so is one whose first cell looks like a header", facts("| F1 | q | ESTABLISHED | x | - |\nX:y | r | CONTRADICTED | x | -\n")[0] != [])
    check("a row without its leading pipe is reported", facts("| F1 | q | ESTABLISHED | x | - |\nF9 | r | CONTRADICTED | x | -\n")[0] != [])
    deep = "".join("| F%d | p | ESTABLISHED | w | F%d |\n" % (i, i + 1) for i in range(3000)) + "| F3000 | p | ESTABLISHED | w | - |\n"
    probs, eff = facts(deep)
    check("a 3000-link chain is judged whole, with no depth limit", not probs and eff["F0"] == "ESTABLISHED")
    probs, eff = facts(deep.replace("| F3000 | p | ESTABLISHED |", "| F3000 | p | RETRACTED |"))
    check("and a retraction at its far end reaches its head", eff["F0"] == "UNKNOWN")
    probs, eff = facts("| F1 | p | ESTABLISHED | w | F2 |\n| F2 | q | ESTABLISHED | w | F1 |\n")
    check("facts resting on each other in a cycle are both UNKNOWN", eff == {"F1": "UNKNOWN", "F2": "UNKNOWN"})
    check("a row with no ID is reported", facts("| | p | CONTRADICTED | x | - |\n| F1 | q | ESTABLISHED | x | - |\n")[0] != [])
    for bad in ("\t@echo x\n#: a 10_x present\nfinish: a\na:\n", "finish: a\n#: a 10_x present\na:\n\t#: b 15_f present\n"):
        try:
            parse_graph(bad); ok = False
        except ValueError:
            ok = True
        check("the graph parser refuses a misplaced tab line", ok)
    check("an escaped pipe at the row's end stays in its cell", facts("| F1 | p | ESTABLISHED | w | F0\\|\n")[1].get("F1") == "UNKNOWN")
    check("an escaped pipe stays inside its cell", not facts("| F1 | p | ESTABLISHED | `ls \\| wc -l` exit 0 | - |\n")[0])
    check("a row with the wrong number of cells is reported", facts("| F1 | a | b | ESTABLISHED | x | - |\n")[0] != [])
    return 1 if fail else 0


if __name__ == "__main__":
    if len(sys.argv) == 1:
        sys.exit(selftest())
    try:
        sys.exit(main(sys.argv[1]))
    except OSError as e:
        print("frontier: %s" % e, file=sys.stderr)
        sys.exit(2)
