# agent_pick: status + label resolution for the tmux agent picker.
#
# core.py holds the per-agent logic as pure functions that take their input
# paths as arguments, so tests can point them at temp dirs. cli.py is the thin
# stdin/stdout entrypoint the bash script invokes; it builds a Paths object
# from argv and calls the same functions.
