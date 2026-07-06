#!/usr/bin/env bash
# superpowers-nudge.sh — UserPromptSubmit hook
#
# Re-asserts the superpowers:using-superpowers discipline on every user prompt,
# from the user-turn side, for emphasis. SessionStart already injects the full
# using-superpowers skill once; that injection decays as the conversation grows,
# so this hook re-states only its CORE forcing rule each turn (not the full
# ~760-word skill, which would be redundant and token-heavy).
#
# For UserPromptSubmit hooks, stdout on exit 0 is injected into the context.
# Unconditional by design: the using-superpowers philosophy is to check EVERY
# message for an applicable skill, so there is no keyword gate.

cat <<'EOF'
<system-reminder>
Before responding to this message, apply the superpowers:using-superpowers discipline:
If there is even a 1% chance a skill might apply to this request, you MUST invoke it via
the Skill tool BEFORE any other response — including clarifying questions. Not optional.
Process skills first (e.g. brainstorming for creative/design work; systematic-debugging
for bugs/failures), then implementation skills. Announce "Using [skill] to [purpose]".
User instructions (CLAUDE.md, direct requests) always take precedence over skills.
</system-reminder>
EOF
exit 0
