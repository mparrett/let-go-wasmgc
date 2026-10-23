#!/usr/bin/env python3
"""subject-lint — check a commit message or PR title against Conventional Commits 1.0.0
(https://www.conventionalcommits.org/en/v1.0.0/).

  subject-lint FILE        a commit message (subject, blank line, body, footers);
                           the commit-msg hook calls it this way
  subject-lint --title T   a PR title (the squash commit's subject)

A message git writes itself passes: `Merge …`, `Revert "…"`, and the
`fixup! ` / `squash! ` / `amend! ` subjects that rebase --autosquash folds away.

Errors (exit 1):
  type          the subject is not `type(scope)!: description`: one of TYPES, an
                optional non-empty (scope), an optional ! (the spec allows other nouns;
                this list keeps an old `area: description` subject from passing as a type)
  space         no single space after the colon
  description   nothing after `type(scope): `
  scope         an empty ()
  blank line    a body or footer not separated from the subject by a blank line
  breaking      a footer `BREAKING CHANGE` without `: ` and a description
Warnings:
  period        a subject ending with a period
In a repo whose subjects were `area: description`, the area is the scope:
`fix(twin-manifest): ...`.
"""
import re
import sys

TYPES = ("feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert")
GIT_WRITTEN = re.compile(r'(Merge |Revert "|fixup! |squash! |amend! )')
SUBJECT = re.compile(r"^(?P<type>[a-z][a-z0-9-]*)(?:\((?P<scope>[^()]*)\))?(?P<bang>!)?:(?P<space>\s*)(?P<desc>.*)$")


def check(msg):
    errors, warnings = [], []
    lines = msg.rstrip("\n").split("\n")
    subject = lines[0].rstrip()
    m = SUBJECT.match(subject)
    if not m:
        errors.append(f"type: '{subject[:60]}' is not type(scope)!: description")
        return errors, warnings
    if m.group("type") not in TYPES:
        area = m.group("type")
        errors.append(f"type: '{area}' is not one of {', '.join(TYPES)}; an area goes in the scope, e.g. fix({area}): ...")
    if m.group("scope") is not None and not m.group("scope").strip():
        errors.append("scope: an empty () names no scope; drop it or name the area")
    if m.group("space") != " ":
        errors.append("space: one space after the colon")
    if not m.group("desc").strip():
        errors.append("description: nothing after the colon")
    elif subject.endswith("."):
        warnings.append("period: a subject is a title, without a final period")
    if len(lines) > 1 and lines[1].strip():
        errors.append("blank line: separate the body from the subject with a blank line")
    for line in lines[1:]:
        if re.match(r"BREAKING[ -]CHANGE\b", line) and not re.match(r"BREAKING[ -]CHANGE: \S", line):
            errors.append("breaking: write the footer as 'BREAKING CHANGE: <description>'")
    return errors, warnings


def main():
    argv = sys.argv[1:]
    if not argv:
        sys.exit(__doc__)
    if argv[0] == "--title":
        msg, where = " ".join(argv[1:]), "title"
    else:
        msg, where = open(argv[0], encoding="utf-8").read(), argv[0]
    # a commit-msg hook's file may carry git's comment lines
    msg = "\n".join(l for l in msg.split("\n") if not l.startswith("#"))
    if GIT_WRITTEN.match(msg.lstrip("\n")):
        print(f"ok: written by git ({where})")
        sys.exit(0)
    errors, warnings = check(msg)
    for e in errors:
        print(f"ERROR   {e}")
    for w in warnings:
        print(f"warning {w}")
    print(f"{'FAIL' if errors else 'ok'}: {len(errors)} errors, {len(warnings)} warnings ({where})")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
