# checks/workflow.mk — the deterministic steps of the workflow, as make targets.
# Judgment calls and human approvals stay with people; anything a script can
# decide is a target here, so it runs every time instead of being remembered.
#
#   make -f checks/workflow.mk start          before taking an issue
#   make -f checks/workflow.mk baseline       the affected rows on origin/main
#   make -f checks/workflow.mk rows           the affected rows on this tree
#   make -f checks/workflow.mk gate PHASE=n   a phase gate, attestation off
#   make -f checks/workflow.mk pushed         after a push: the issue notes went too
#   make -f checks/workflow.mk pr-ready TITLE="..." BODY=file   before gh pr create/edit
#   make -f checks/workflow.mk ci PR=n        the PR's checks, once: 0 green, 1 red, 3 running
#
# ROWS="<id> ..." overrides the affected rows. checks/state-template/00_governance.md
# has the whole lifecycle; the human approvals between these targets live there.
SHELL := bash
W := checks/workflow.sh

.PHONY: start hooks in-flight baseline rows gate pushed pr-ready ci selftest

start: hooks in-flight

# the clone's setup: prek's and git-issue's hooks, and the fetch of the
# evidence notes (README.md, Issues)
hooks:
	@$(W) hooks
	@$(W) fetch-config

in-flight:
	@checks/state.sh inflight

baseline:
	@$(W) baseline $(ROWS)

rows:
	@$(W) rows $(ROWS)

gate: rows
	@: $${PHASE:?usage: make -f checks/workflow.mk gate PHASE=<n>}
	LW_ATTEST=0 checks/gate.sh $(PHASE)

pushed: hooks
	@$(W) pushed

pr-ready:
	@: $${TITLE:?usage: make -f checks/workflow.mk pr-ready TITLE=... BODY=file} $${BODY:?BODY=file}
	@$(W) pr-ready "$(TITLE)" "$(BODY)"

ci:
	@: $${PR:?usage: make -f checks/workflow.mk ci PR=<n>}
	@$(W) ci $(PR)

selftest:
	@checks/state.sh
	@$(W)
	@checks/subject-lint-cases.sh
	@checks/comment-lint-cases.sh
