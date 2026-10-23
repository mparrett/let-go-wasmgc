#!/usr/bin/env python3
"""comment-lint — check a draft PR/issue comment before it is posted as the user.

  comment-lint FILE                  errors exit 1; warnings print but pass

Style: the answer first, then the evidence, then any ask; and Strunk's
Elements of Style. Length is not a rule: Strunk's "omit needless words" asks
that every word tell, not that the text be short, so the lint flags the
patterns that waste words instead of counting them.

Use it on anything posted from your account: PR descriptions, PR and issue
comments, git-issue bodies. The poster's identity comes from `gh api user`
(login, name) and `git config user.name`.
Errors (the comment must change):
  self-mention      @<own login>: the comment is posted by that account
  third-person      the user's name or login used as a third party
  agent-voice       Claude / a subagent / "as an AI" / session talk
  footer            "Generated with", robot emoji, Co-Authored-By, "Drafted with ..."
Warnings (fix unless there is a reason):
  needless          Strunk 13: "the fact that", "in order to", "basically", "actually" ...
  passive           Strunk 10: "was moved by #57"; say who did it, as the subject
  negative          Strunk 11: "not very often", "did not remember"; say what is
  loose             Strunk 14: three sentences in a row of two clauses joined by
                    ", and" / ", but" / ", which" ...
  narration         the steps taken ("First I ran ... Then I checked ..."); give the result
  opener            thanks / "great point" / context openers ("To give some context");
                    start with the answer
  personal          codereview-comments: "why did you", "you forgot", "your code";
                    comment on the code, not the person
  headings          markdown headings in a comment of a few paragraphs
  hedge             "should work", "I think", "probably", "it seems"
  sha               a commit SHA; cite the PR or issue number instead (a git-issue id
                    written git-issue:<id> is exempt)
  third-person?     "the user" / "the author": wrong when it means the person posting
"""
import json
import re
import subprocess
import sys


def identity():
    names = set()
    login = ""
    p = subprocess.run(["gh", "api", "user"], capture_output=True, text=True)
    if p.returncode == 0:
        u = json.loads(p.stdout)
        login = u.get("login") or ""
        if u.get("name"):
            names.add(u["name"])
    p = subprocess.run(["git", "config", "user.name"], capture_output=True, text=True)
    if p.returncode == 0 and p.stdout.strip():
        names.add(p.stdout.strip())
    parts = set()
    for n in names:
        parts.add(n)
        first = n.split()[0].strip(",")
        if len(first) > 2:
            parts.add(first)
    return login, sorted(parts)


def strip_code(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    return re.sub(r"`[^`\n]*`", " ", text)


def main():
    argv = sys.argv[1:]
    if not argv:
        sys.exit(__doc__)
    path = argv[0]
    raw = open(path, encoding="utf-8").read()
    prose = strip_code(raw)
    words = len(prose.split())
    login, names = identity()

    errors, warnings = [], []

    def hits(pattern, text=prose, flags=re.I):
        return sorted({m.group(0).strip() for m in re.finditer(pattern, text, flags)})

    if login:
        h = hits(rf"@{re.escape(login)}\b")
        if h:
            errors.append(f"self-mention {h}: the comment is posted as {login}")
        # a bare login outside a repo path (owner/repo, owner:branch) names the user in the third person
        h = [m.group(0) for m in re.finditer(rf"(?<![@/\w]){re.escape(login)}(?![/:\w])", prose, re.I)]
        if h:
            errors.append(f"third-person {sorted(set(h))}: write as {login}, in the first person")
    for n in names:
        h = hits(rf"\b{re.escape(n)}\b", flags=0)
        if h:
            errors.append(f"third-person {h}: the comment is written as this person")
    h = hits(r"\b(the user|my (?:human )?partner|the (?:PR |issue )?author|the requester)\b")
    if h:
        warnings.append(f"third-person? {h}: fine for a library's user; wrong if it means the person posting")
    h = hits(r"\b(claude(?: code)?|as an ai|an ai assistant|language model|subagents?|my session|this session|another session)\b")
    if h:
        errors.append(f"agent-voice {h}: the comment speaks as the user, not as a tool")
    h = hits(r"(Generated with|🤖|Co-Authored-By|[Dd]rafted with|written with the help|posted with .{0,20}help|checked by me)", raw, flags=0)
    if h:
        errors.append(f"footer {h}: no attribution footers or disclosure lines in comments")
    paragraphs = [p for p in re.split(r"\n\s*\n", prose) if p.strip()]
    if len(paragraphs) < 5 and re.search(r"^#{1,6} ", raw, re.M):
        warnings.append("headings: a comment of a few paragraphs reads better without them")
    first = prose.strip().split("\n", 1)[0]
    if re.match(r"\W*(thanks|thank you|great (point|catch|question)|good catch|you'?re (absolutely )?right"
                r"|to give (some )?context|for (some )?context|some context|background\b|as (you know|discussed|mentioned)"
                r"|just (wanted|a quick)|following up|quick (note|update))", first, re.I):
        warnings.append(f"opener: '{first[:40]}': start with the answer")
    sentences = [x.strip() for x in re.split(r"(?<=[.!?])\s+|\n(?=\s*(?:[-*]|\d+\.)\s)", prose) if x.strip()]
    h = hits(r"\b(the fact that|the question as to whether|there is no doubt but that|in order to|basically|actually"
             r"|really|very|simply|needless to say|it should be noted|(?:it is )?worth noting|note that|i wanted to|i'?d like to"
             r"|in an? \w+ manner|at the end of the day)\b")
    if h:
        warnings.append(f"needless {h}: Strunk 13, omit needless words")
    h = hits(r"\b(?:is|are|was|were|be|been|being)\s+(?:\w+ed|\w+en|built|done|made|run|set|put|kept|held|found"
             r"|shown|known|given|seen|left|sent|read|hit|caught)\s+by\b")
    if h:
        warnings.append(f"passive {h}: Strunk 10, make the doer the subject")
    h = hits(r"\bnot\s+(?:very\s+)?(?:often|honest|important|much|many|clear|useful|always)\b"
             r"|\bdid not (?:remember|pay (?:any )?attention|have much confidence)\b")
    if h:
        warnings.append(f"negative {h}: Strunk 11, say what is, not what is not")
    loose = [bool(re.search(r",\s+(?:and|but|so|which|while|when|where|who)\b", x, re.I)) for x in sentences]
    if any(all(loose[i:i + 3]) for i in range(len(loose) - 2)):
        warnings.append("loose: three sentences in a row each join two clauses with ', and' / ', but' / ', which';"
                        " Strunk 14, recast some of them")
    h = hits(r"\b(why did you|why didn'?t you|you (?:forgot|didn'?t|did not|should have|failed to|missed|broke)|your code)\b")
    if h:
        warnings.append(f"personal {h}: codereview-comments, comment on the code, not the person")
    steps = [x for x in sentences if re.match(r"(?:first|then|next|after that|afterwards|finally|once that was done)\b,?\s+i\b", x, re.I)]
    if len(steps) >= 2:
        warnings.append(f"narration {[x[:30] for x in steps[:3]]}: give the result, not the steps taken")
    # a git-issue id is written git-issue:<id> on purpose, so it is not a SHA
    shas = sorted({m.group(1) for m in re.finditer(r"(?<![\w/#-])([0-9a-f]{7,40})(?![\w-])", raw)
                   if re.search(r"[0-9]", m.group(1)) and re.search(r"[a-f]", m.group(1))
                   and not raw[:m.start()].endswith("git-issue:")})
    if shas:
        warnings.append(f"sha {shas[:4]}: readers follow PR and issue numbers, not commit SHAs; cite the PR")
    h = hits(r"\b(should work|should be fine|i think|probably|it seems|looks correct)\b")
    if h:
        warnings.append(f"hedge {h}: state what was verified, or say what is unverified")

    for e in errors:
        print(f"ERROR   {e}")
    for w in warnings:
        print(f"warning {w}")
    print(f"{'FAIL' if errors else 'ok'}: {words} words, {len(errors)} errors, {len(warnings)} warnings ({path})")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
