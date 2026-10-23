# checks/workflow.mk — the deterministic steps of the workflow, as make targets.
# Judgment calls and human approvals stay with people; anything a script can
# decide is a target here, so it runs every time instead of being remembered.
#
#   make -f checks/workflow.mk start          before taking an issue
#   make -f checks/workflow.mk baseline       the affected rows on the diff's base (merge-base with origin/main)
#   make -f checks/workflow.mk rows           the affected rows on this tree
#   make -f checks/workflow.mk gate PHASE=n   a phase gate, attestation off
#   make -f checks/workflow.mk pushed         after a push: the issue notes went too
#   make -f checks/workflow.mk pr-ready TITLE="..." BODY=file   before gh pr create/edit
#   make -f checks/workflow.mk ci PR=n        the PR's checks, once: 0 green, 1 red, 3 running
#   make -f checks/workflow.mk next ISSUE=id  the issue's realized and ready steps (checks/frontier.py
#                                             over checks/lifecycle.mk and the issue's ledger)
#   make -f checks/workflow.mk critic ISSUE=id   the branch diff for the un-primed critic
#   make -f checks/workflow.mk record-rows ISSUE=id / record-gate ISSUE=id
#                                             run the step; record its entry only when it passes
#   make -f checks/workflow.mk declare ISSUE=id ENTRY=20_plan|45_review_ok|50_commit|60_push
#                                             the operator's declaration; run it in your own shell
#
# ROWS="<id> ..." overrides the affected rows. The lifecycle these targets serve is
# checks/lifecycle.mk; checks/state-template/00_governance.md has its rules.
SHELL := bash
W := checks/workflow.sh

.PHONY: start hooks in-flight ready baseline rows gate pushed pr-ready ci next critic record-rows record-gate declare selftest

start: hooks in-flight ready

ready:
	@git issue ready 2>/dev/null

hooks:
	@$(W) hooks

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

next:
	@: $${ISSUE:?usage: make -f checks/workflow.mk next ISSUE=<id>}
	@checks/frontier.py $(ISSUE)

record-rows:
	@: $${ISSUE:?usage: make -f checks/workflow.mk record-rows ISSUE=<id>}
	@$(W) record-rows $(ISSUE)

record-gate:
	@: $${ISSUE:?usage: make -f checks/workflow.mk record-gate ISSUE=<id>}
	@$(W) record-gate $(ISSUE)

declare:
	@: $${ISSUE:?usage: make -f checks/workflow.mk declare ISSUE=<id> ENTRY=<entry> [NOTE=...]} $${ENTRY:?ENTRY=20_plan|45_review_ok|50_commit|60_push}
	@$(W) declare $(ISSUE) $(ENTRY) "$$NOTE"

critic:
	@: $${ISSUE:?usage: make -f checks/workflow.mk critic ISSUE=<id>}
	@$(W) critic $(ISSUE)

selftest:
	@checks/state.sh
	@$(W)
	@checks/subject-lint-cases.sh
	@checks/comment-lint-cases.sh
	@checks/frontier.py
