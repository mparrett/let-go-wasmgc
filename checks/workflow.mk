# checks/workflow.mk — the deterministic steps of the workflow, as make targets.
# Judgment calls and human approvals stay with people; anything a script can
# decide is a target here, so it runs every time instead of being remembered.
#
#   make -f checks/workflow.mk start          before taking an issue
#   make -f checks/workflow.mk baseline       the affected rows on origin/main
#   make -f checks/workflow.mk rows           the affected rows on this tree
#   make -f checks/workflow.mk gate PHASE=n   a phase gate, attestation off
#   make -f checks/workflow.mk pushed         after a push: the issue notes went too
#
# ROWS="<id> ..." overrides the affected rows. checks/state-template/00_governance.md
# has the whole lifecycle; the human approvals between these targets live there.
SHELL := bash
W := checks/workflow.sh

.PHONY: start hooks in-flight baseline rows gate pushed selftest

start: hooks in-flight

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

selftest:
	@checks/state.sh
	@$(W)
