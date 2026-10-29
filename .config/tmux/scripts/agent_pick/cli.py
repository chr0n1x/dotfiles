"""stdin/stdout entrypoint for the tmux agent picker.

The bash script pipes one line per pane on stdin (pane_id TAB agent TAB pid
TAB cwd, agent and pid empty when the pane runs none) and gets one line back
per input line: status US label, where US is \037 (a non-whitespace byte so an
empty status survives the reader's word-splitting). The ps snapshot arrives in
AGENT_PICK_SNAP; the session roots in argv.

This is a one-to-one lift of the original heredoc's tail: it sets core's
globals via core.init() (the original did this at import from sys.argv and
os.environ), then runs the same per-pane loop over sys.stdin. All the per-agent
logic lives in core.py, verbatim from the original.
"""

import os
import re
import sys

import agent_pick.core as core


def main(argv):
    core.init(
        argv[0], argv[1], argv[2], argv[3],
        argv[4], argv[5], argv[6],
        os.environ.get("AGENT_PICK_SNAP", ""),
    )
    for ln in sys.stdin:
        # pane TAB <name1 pid1 name2 pid2 ...> TAB cwd. The pane id (field 1)
        # is carried for parity with the bash path but unused here: status and
        # label are resolved from the agent pairs + cwd, not the pane id.
        _pane, pairs, cwd = (ln.rstrip("\n").split("\t") + ["", "", ""])[:3]
        toks = pairs.split()
        agent_pairs = [(toks[i], toks[i + 1]) for i in range(0, len(toks) - 1, 2)]
        st = lb = ""
        if agent_pairs:
            # Status is aggregated across every agent: any working -> working
            # (blue), else any idle -> idle (green), else unknown (gray). The
            # lualine uses the same rule, so a pane reads the same in both.
            try:
                sts = []
                for name, pid in agent_pairs:
                    try:
                        sts.append(core.status(name, pid, cwd))
                    except Exception:  # noqa: BLE001 - one agent's failure -> unknown for it
                        sts.append("unknown")
                st = core.reduce_status(sts)
            except Exception:  # noqa: BLE001 - whole-pane status failure -> unknown
                st = "unknown"
            try:
                # Shortest non-empty session name across every agent in the
                # pane, so a primary with no label still shows a sibling's.
                lb = core.shortest_label(agent_pairs, cwd)
            except Exception:  # noqa: BLE001 - label failure -> no label, not an error
                lb = ""
        print(st + "\037" + re.sub(r"[\t\r\n\037]+", " ", lb).strip())


if __name__ == "__main__":
    main(sys.argv[1:8])
