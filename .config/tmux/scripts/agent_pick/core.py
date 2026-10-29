"""agent_pick: status + label for the tmux agent picker.

A one-to-one lift of the python that used to live inline in
tmux-agent-pick.sh. The functions below are verbatim copies of the original
heredoc; the only change is that the argv/env parsing and the stdin/stdout
loop moved to cli.py. The module-level globals (claude_sessions, etc.) are set
by cli.main() before the functions run, exactly as the original set them at
import time. Tests set the same globals directly.
"""

import glob
import json
import os
import re

(claude_sessions, claude_projects, maki_sessions, copilot_store,
 copilot_state, pi_sessions, pig_sessions) = ("",) * 7

kids = {}


def ro(db):
    # Lazy import: sqlite3 is only needed for crush and copilot, and importing
    # it costs ~20ms. Deferring it keeps the module load fast for the common
    # case (no crush/copilot pane in the list).
    import sqlite3
    return sqlite3.connect("file:" + db + "?mode=ro", uri=True)


def tail(path, n):
    with open(path, "rb") as fh:
        fh.seek(0, 2)
        fh.seek(max(0, fh.tell() - 262144))
        data = fh.read().decode("utf-8", "replace")
    return data.splitlines()[-n:]


def newest(paths):
    paths = [x for x in paths if os.path.exists(x)]
    return max(paths, key=os.path.getmtime) if paths else None


def pi_file(root, cwd):
    # --<cwd>-- with the leading slash stripped and /, \, : turned into -.
    if not cwd:
        return None
    d = os.path.join(root, "--" + re.sub(r"[/\\:]", "-", cwd.removeprefix("/")) + "--")
    return newest(glob.glob(os.path.join(d, "*.jsonl")))


def copilot_dir(pid):
    # A copilot process can hold inuse.<pid>.lock in several session dirs
    # (resumed sessions leave stale locks). The live one has the newest
    # events.jsonl; with no events anywhere, the newest lock wins.
    locks = glob.glob(os.path.join(copilot_state, f"inuse.{pid}.lock")) + \
        glob.glob(os.path.join(copilot_state, "*", f"inuse.{pid}.lock"))
    if not locks:
        return None
    ev = newest([os.path.join(os.path.dirname(x), "events.jsonl") for x in locks])
    if ev:
        return os.path.dirname(ev)
    # No events.jsonl anywhere: the newest lock's dir wins. locks is non-empty
    # here, so newest(locks) is a path, but newest's signature allows None, so
    # guard it rather than trust the guard above.
    best = newest(locks)
    return os.path.dirname(best) if best else None


def child_status(pid):
    return "working" if kids.get(pid, 0) > 0 else "idle"


def status(name, pid, cwd):
    if name == "copilot":
        # A turn_start with no later turn_end means a turn is in progress. The
        # child check is unusable: copilot keeps helper subprocesses when idle.
        d = copilot_dir(pid)
        if not d:
            return "unknown"
        ev = os.path.join(d, "events.jsonl")
        if not os.path.exists(ev):
            return "idle"
        marks = re.findall(r'"assistant\.turn_(start|end)"', "\n".join(tail(ev, 400)))
        return "working" if marks and marks[-1] == "start" else "idle"
    if name == "pig":
        # pig keeps a node child (its extension runtime) alive, so read the
        # turn state instead: the last message being an assistant that stopped
        # (stop/aborted/error) means idle; anything else in flight is working.
        f = pi_file(pig_sessions, cwd)
        if not f:
            return "idle"
        last = None
        for ln in tail(f, 200):
            try:
                e = json.loads(ln)
            except Exception:  # noqa: S112,BLE001 - malformed line skipped, picker swallows stderr
                continue
            if e.get("type") == "message" and isinstance(e.get("message"), dict):
                last = e["message"]
        if last is None or last.get("role") == "system":
            return "idle"
        if last.get("role") == "assistant" and last.get("stopReason") in ("stop", "aborted", "error"):
            return "idle"
        return "working"
    if name == "crush":
        # Only assistant messages ever get finished_at, so a newest message
        # with finished_at NULL means a turn is in progress.
        db = os.path.join(cwd, ".crush", "crush.db")
        if not os.path.exists(db):
            return "unknown"
        r = ro(db).execute("SELECT finished_at FROM messages ORDER BY created_at DESC, rowid DESC LIMIT 1").fetchone()
        return "working" if (r is not None and r[0] is None) else "idle"
    if name == "claude":
        f = os.path.join(claude_sessions, pid + ".json")
        if os.path.exists(f):
            try:
                with open(f) as fh:
                    st = json.load(fh).get("status", "")
            except Exception:  # noqa: BLE001 - unreadable session file degrades to "unset", not an error
                st = ""
            if st == "busy":
                return "working"
            if st:
                return "idle"
    # Child check: maki and the rest show tool/bash execution as a child
    # process; pure text generation has no per-pid signal.
    return child_status(pid)


def label(name, pid, cwd):
    # A label is best-effort: a session file may be mid-write, just created,
    # or unreadable, and any of that means "no label yet", not an error. The
    # whole lookup is wrapped so label() never leaks an exception regardless of
    # caller - a missing/empty label degrades to "".
    try:
        return _label_impl(name, pid, cwd)
    except Exception:  # noqa: BLE001 - any I/O or parse failure -> no label
        return ""


def _label_impl(name, pid, cwd):
    # Called only from label(), which wraps it in try/except and degrades any
    # I/O or parse failure to "". The open()/json calls below are therefore
    # intentionally unguarded here: a missing/corrupt session file means "no
    # label yet", and the caller owns the fallback. (pyright/flow-analysis
    # tools that don't see across the call boundary flag these; the guard is
    # real, in label().)
    if name == "claude":
        # A user rename lives in the session file's name (nameSource absent or
        # not "derived"); otherwise the last ai-title in the project jsonl.
        # pyright: ignore - open()/json handled by label()'s caller-side try/except
        with open(os.path.join(claude_sessions, pid + ".json")) as fh:
            d = json.load(fh)
        if d.get("name") and d.get("nameSource", "") != "derived":
            return d["name"]
        sid = d.get("sessionId", "looked-up-below")
        proj = (glob.glob(os.path.join(claude_projects, sid + ".jsonl")) +
                glob.glob(os.path.join(claude_projects, "*", sid + ".jsonl")))
        if not proj:
            return ""
        last = ""
        # pyright: ignore - open()/json handled by label()'s caller-side try/except
        with open(proj[0], encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                if '"ai-title"' in ln:
                    last = ln
        return json.loads(last).get("aiTitle", "") if last else ""
    if name == "maki":
        # cwd_latest.json maps cwd -> sid of the newest session started there.
        # pyright: ignore - open()/json handled by label()'s caller-side try/except
        with open(os.path.join(maki_sessions, "cwd_latest.json")) as fh:
            sid = json.load(fh).get(cwd, "")
        if not sid:
            return ""
        last = ""
        # pyright: ignore - open()/json handled by label()'s caller-side try/except
        with open(os.path.join(maki_sessions, sid + ".jsonl"), encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                if '"t":"meta"' in ln:
                    last = ln
        return json.loads(last).get("title", "") if last else ""
    if name in ("pi", "pig"):
        # Last session_info.name (user/auto title), else the first user message.
        f = pi_file(pig_sessions if name == "pig" else pi_sessions, cwd)
        if not f:
            return ""
        nm = first = ""
        with open(f, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                # A malformed line is skipped, not logged: the picker has no
                # logger and runs with stderr swallowed (S112/BLE001 intentional).
                try:
                    e = json.loads(ln)
                except Exception:  # noqa: S112,BLE001 - malformed line skipped; picker swallows stderr
                    continue
                if e.get("type") == "session_info" and e.get("name"):
                    nm = e["name"]
                elif not first and e.get("type") == "message":
                    m = e.get("message", {})
                    if m.get("role") == "user":
                        c = m.get("content", "")
                        if isinstance(c, list):
                            texts = [b.get("text", "") for b in c
                                     if isinstance(b, dict) and b.get("type") == "text"]
                            c = " ".join(texts)
                        first = (c or "").strip().replace("\n", " ")
        t = nm or first
        return t[:63] + "\u2026" if len(t) > 64 else t
    if name == "crush":
        db = os.path.join(cwd, ".crush", "crush.db")
        if not os.path.exists(db):
            return ""
        r = ro(db).execute("SELECT title FROM sessions ORDER BY updated_at DESC LIMIT 1").fetchone()
        return r[0] if r and r[0] else ""
    if name == "copilot":
        # pid -> exact session via its inuse lock, then that session's summary;
        # the short session id when it has none yet.
        if not os.path.exists(copilot_store):
            return ""
        d = copilot_dir(pid)
        if not d:
            return ""
        sid = os.path.basename(d)
        r = ro(copilot_store).execute("SELECT summary FROM sessions WHERE id=?", (sid,)).fetchone()
        return r[0] if r and r[0] else sid[:8]
    return ""


def shortest_label(pairs, cwd):
    """Shortest non-empty session name across a pane's agents.

    pairs is a list of (name, pid) in priority order. A pane can run several
    agents, and each resolves its own session name (labels are per-pid). The
    primary agent may have no resolvable name (e.g. a fresh claude session with
    no ai-title) even though a sibling does, so we resolve every agent and show
    the shortest non-empty one - compact, and non-blank when any agent has a
    label. Returns "" when none do.
    """
    best = ""
    for name, pid in pairs:
        try:
            t = (label(name, pid, cwd) or "").strip()
        except Exception:  # noqa: BLE001 - any label failure degrades to "" for that agent
            t = ""
        if t and (best == "" or len(t) < len(best)):
            best = t
    return best


def reduce_status(statuses):
    """Aggregate a pane's per-agent statuses into one icon state.

    Any agent working -> "working" (blue dot: something is happening in this
    pane). Else any idle -> "idle" (green check: all done/waiting). Else
    "unknown" (gray ?). Matches the lualine's aggregate rule
    (harness-decorators/agent-display.lua). An empty list is "unknown" - but the
    caller only reaches here with at least one agent (no-agent panes get their
    own gray dot upstream).
    """
    s = list(statuses)
    if any(x == "working" for x in s):
        return "working"
    if any(x == "idle" for x in s):
        return "idle"
    return "unknown"


def init(claude_sessions_, claude_projects_, maki_sessions_, copilot_store_,
         copilot_state_, pi_sessions_, pig_sessions_, snap):
    """Set the module globals from argv values + the ps snapshot. Called by
    cli.main() before the per-pane loop; the original did this at import time
    from sys.argv and os.environ. Kept as a function so tests can call it with
    temp dirs instead of relying on import-time side effects."""
    global claude_sessions, claude_projects, maki_sessions, copilot_store
    global copilot_state, pi_sessions, pig_sessions, kids
    claude_sessions = claude_sessions_
    claude_projects = claude_projects_
    maki_sessions = maki_sessions_
    copilot_store = copilot_store_
    copilot_state = copilot_state_
    pi_sessions = pi_sessions_
    pig_sessions = pig_sessions_
    kids = {}
    for ln in (snap or "").splitlines():
        f = ln.split()
        if len(f) >= 2:
            kids[f[1]] = kids.get(f[1], 0) + 1
