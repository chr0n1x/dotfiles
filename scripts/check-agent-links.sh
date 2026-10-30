#!/bin/sh
# Every harness skills/commands dir links into agents/, pi/pig load the shared
# system prompt, and every skill and command resolves.
# Run from the repo root: `make test-agent-links`.
fail=0
err() { echo "FAIL: $*"; fail=1; }

check_link() { # <path> <expected relative target>
	[ "$(readlink "$1")" = "$2" ] || err "$1 -> $(readlink "$1"), want $2"
}
check_link .claude/skills ../agents/skills
check_link .claude/commands ../agents/commands
check_link .copilot/skills ../agents/skills
for h in .pi/agent .pig/agent; do
	check_link $h/skills ../../agents/skills
	check_link $h/prompts ../../agents/commands
	check_link $h/AGENTS.md ../../SYSTEM_PROMPT.md
done

for d in agents/skills/*/; do
	[ -f "${d}SKILL.md" ] || err "${d}SKILL.md missing or dangling"
done
for f in agents/commands/*.md; do
	[ -f "$f" ] || err "$f dangling"
done

set -- agents/skills/*/
skills=$#
set -- agents/commands/*.md
[ $fail = 0 ] && echo "agent links OK ($skills skills, $# commands)"
exit $fail
