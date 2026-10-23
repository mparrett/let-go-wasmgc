# checks/lifecycle.mk — one issue's lifecycle as a make graph, in the notation
# of Randal Schwartz's ticket workflow: a target is an outcome, its
# prerequisites are what it rests on, and a recipe names the step. Nothing
# here is run by make. The agent reads the graph, and checks/frontier.py
# computes which steps are realized and which are ready, from the issue's
# local ledger (checks/state.sh) and the tree:
#
#   make -f checks/workflow.mk next ISSUE=<id>
#
# Each `#:` line gives a step's ledger entry and the rule that realizes it:
#   present        the entry exists
#   facts          the entry's Belnap table has at least one fact; judging each
#                  ID by its latest row, every row is well formed, no fact is
#                  CONTRADICTED, and no ESTABLISHED fact rests, directly or
#                  through others, on one RETRACTED, UNKNOWN or CONTRADICTED
#   diff           the entry's Diff-Sha is the branch's diff now
#   declared:<b>   the operator wrote it (checks/workflow.sh declare, run in
#                  the operator's own shell) and its Diff-Sha or Facts-Sha
#                  is current; an agent never writes one

#: in-flight-reviewed  05_inflight   present
#: issue-opened        10_issue      present
#: facts-recorded      15_facts      facts
#: plan-approved       20_plan       declared:facts
#: rows-green          30_rows       diff
#: gate-green          35_gate       diff
#: critic-reviewed     40_review     diff
#: review-approved     45_review_ok  declared:diff
#: commit-approved     50_commit     declared:diff
#: push-approved       60_push       declared:diff
#: retro-recorded      90_retro      present

finish: retro-recorded
retro-recorded: push-approved
	@echo "[90] the retro: nudges, critic findings, breaker trips, the lessons they leave"
push-approved: commit-approved
	@echo "[60] the operator declares the push; then make -f checks/workflow.mk pushed, ci"
commit-approved: review-approved
	@echo "[50] the operator declares the commit"
review-approved: critic-reviewed
	@echo "[45] the operator declares the review, after reading the critic's findings"
critic-reviewed: gate-green
	@echo "[40] make -f checks/workflow.mk critic ISSUE=...; an un-primed, read-only critic; its findings are the entry"
gate-green: rows-green
	@echo "[35] make -f checks/workflow.mk record-gate ISSUE=..."
rows-green: plan-approved
	@echo "[30] make -f checks/workflow.mk record-rows ISSUE=...: each row on the base and on the tree"
plan-approved: facts-recorded
	@echo "[20] the operator declares the plan"
facts-recorded: issue-opened
	@echo "[15] the facts the plan rests on, a Belnap table row each: | ID | Proposition | Status | Evidence | DependsOn |"
issue-opened: in-flight-reviewed
	@echo "[10] the request: branch, base, conditions of satisfaction"
in-flight-reviewed:
	@echo "[05] make -f checks/workflow.mk start; a disposition for every in-flight item"
