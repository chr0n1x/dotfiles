"""Tests for agent_pick.core.

The functions are a one-to-one lift of the inline heredoc in
tmux-agent-pick.sh: they read module-level globals (claude_sessions, etc.)
rather than taking paths as arguments. Tests point those globals at temp dirs
via core.init(), then call the functions exactly as the picker does.

Run with:  python3 -m pytest .config/tmux/tests/test_agent_pick.py -v
"""

from __future__ import annotations

import json
import os
import sqlite3
import sys
from typing import TYPE_CHECKING

import pytest

# Make the package importable regardless of where pytest is run from. The
# scripts dir (containing the agent_pick package) is the import root.
_SCRIPTS = os.path.join(os.path.dirname(__file__), "..", "scripts")
sys.path.insert(0, _SCRIPTS)

# The type checker runs before the sys.path line above, so it can't resolve the
# package from there. The import root is the scripts dir; declaring it here lets
# pyright find agent_pick.* without a config file.
# pyright: reportMissingImports=false

import agent_pick.cli as cli  # noqa: E402 - must follow the sys.path insert
import agent_pick.core as core  # noqa: E402 - must follow the sys.path insert

if TYPE_CHECKING:  # pragma: no cover - satisfied statically, never runs
    _ = os.path.join(_SCRIPTS, "agent_pick")


def write(path, text):
    path = str(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    return path


@pytest.fixture
def env(tmp_path):
    """Point every core global at a fresh subdir under tmp_path."""
    def sub(name):
        d = tmp_path / name
        d.mkdir()
        return str(d)
    copilot_store = str(tmp_path / "copilot_store.db")
    core.init(
        sub("claude_sessions"), sub("claude_projects"), sub("maki_sessions"),
        copilot_store, sub("copilot_state"), sub("pi_sessions"), sub("pig_sessions"),
        "",
    )
    return tmp_path


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def test_kids_built_from_snap():
    core.init("", "", "", "", "", "", "", "1 0 init\n2 1 a\n3 1 b\n4 2 c\n5 0 d")
    assert core.kids == {"0": 2, "1": 2, "2": 1}


def test_kids_empty_snap():
    core.init("", "", "", "", "", "", "", "")
    assert core.kids == {}


def test_child_status_working():
    core.init("", "", "", "", "", "", "", "9 1 x")
    assert core.child_status("1") == "working"


def test_child_status_idle():
    core.init("", "", "", "", "", "", "", "")
    assert core.child_status("1") == "idle"


def test_newest_picks_mtime(tmp_path):
    a = write(tmp_path / "a", "old")
    b = write(tmp_path / "b", "new")
    os.utime(a, (1000, 1000))
    os.utime(b, (2000, 2000))
    assert core.newest([a, b]) == b


def test_newest_skips_missing(tmp_path):
    a = write(tmp_path / "a", "x")
    assert core.newest([a, str(tmp_path / "nope")]) == a


def test_newest_none_when_nothing_exists(tmp_path):
    assert core.newest([str(tmp_path / "x"), str(tmp_path / "y")]) is None


def test_tail_reads_last_n_lines(tmp_path):
    f = write(tmp_path / "log.txt", "\n".join("line%d" % i for i in range(100)) + "\n")
    assert core.tail(f, 3) == ["line97", "line98", "line99"]


def test_tail_fewer_lines_than_n(tmp_path):
    f = write(tmp_path / "log.txt", "a\nb\nc")
    assert core.tail(f, 10) == ["a", "b", "c"]


# ---------------------------------------------------------------------------
# pi_file
# ---------------------------------------------------------------------------

def test_pi_file_maps_cwd_to_dir(tmp_path):
    root = str(tmp_path / "pi")
    s = write(os.path.join(root, "--home-user-proj--", "abc.jsonl"), "{}\n")
    assert core.pi_file(root, "/home/user/proj") == s


def test_pi_file_strips_colons_and_backslashes(tmp_path):
    root = str(tmp_path / "pi")
    # C:/Users/x -> C- (colon) + - (slash) + Users-x = C--Users-x
    write(os.path.join(root, "--C--Users-x--", "s.jsonl"), "{}\n")
    assert core.pi_file(root, "C:/Users/x") == os.path.join(root, "--C--Users-x--", "s.jsonl")
    # a\b -> a-b (backslash)
    write(os.path.join(root, "--a-b--", "s.jsonl"), "{}\n")
    assert core.pi_file(root, "a\\b") == os.path.join(root, "--a-b--", "s.jsonl")


def test_pi_file_empty_cwd_returns_none(tmp_path):
    assert core.pi_file(str(tmp_path / "pi"), "") is None


def test_pi_file_no_session_returns_none(tmp_path):
    assert core.pi_file(str(tmp_path / "pi"), "/home/none") is None


def test_pi_file_picks_newest(tmp_path):
    root = str(tmp_path / "pi")
    d = os.path.join(root, "--home-x--")
    old = write(os.path.join(d, "old.jsonl"), "{}\n")
    new = write(os.path.join(d, "new.jsonl"), "{}\n")
    os.utime(old, (1000, 1000))
    os.utime(new, (2000, 2000))
    assert core.pi_file(root, "/home/x") == new


# ---------------------------------------------------------------------------
# copilot_dir
# ---------------------------------------------------------------------------

def test_copilot_dir_no_locks_returns_none(env):
    assert core.copilot_dir("123") is None


def test_copilot_dir_single_lock_with_events(env):
    d = env / "copilot_state" / "sessA"
    d.mkdir()
    write(d / "inuse.42.lock", "")
    write(d / "events.jsonl", "{}\n")
    assert core.copilot_dir("42") == str(d)


def test_copilot_dir_picks_newest_events_among_stale_locks(env):
    stale = env / "copilot_state" / "stale"
    live = env / "copilot_state" / "live"
    for d in (stale, live):
        d.mkdir()
        write(d / "inuse.42.lock", "")
        write(d / "events.jsonl", "{}\n")
    os.utime(str(stale / "events.jsonl"), (1000, 1000))
    os.utime(str(live / "events.jsonl"), (2000, 2000))
    assert core.copilot_dir("42") == str(live)


def test_copilot_dir_falls_back_to_newest_lock_without_events(env):
    a = env / "copilot_state" / "a"
    b = env / "copilot_state" / "b"
    for d in (a, b):
        d.mkdir()
        write(d / "inuse.42.lock", "")
    os.utime(str(a / "inuse.42.lock"), (1000, 1000))
    os.utime(str(b / "inuse.42.lock"), (2000, 2000))
    assert core.copilot_dir("42") == str(b)


def test_copilot_dir_subdir_locks(env):
    # Locks may sit one level deep under copilot_state (resumed sessions).
    d = env / "copilot_state" / "sess"
    d.mkdir()
    write(d / "inuse.7.lock", "")
    write(d / "events.jsonl", "{}\n")
    assert core.copilot_dir("7") == str(d)


# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

def test_status_maki_child_check(env):
    # snap line "20 9 x" = pid 20 whose ppid is 9, so 9 has a child.
    core.init(*_globals(env), "20 9 x")
    assert core.status("maki", "9", "/x") == "working"
    core.init(*_globals(env), "")
    assert core.status("maki", "9", "/x") == "idle"


def _globals(env):
    """The seven path globals, in core.init order, from the env fixture."""
    return (str(env / "claude_sessions"), str(env / "claude_projects"),
            str(env / "maki_sessions"), str(env / "copilot_store.db"),
            str(env / "copilot_state"), str(env / "pi_sessions"),
            str(env / "pig_sessions"))


def test_status_claude_busy(env):
    write(env / "claude_sessions" / "10.json", json.dumps({"status": "busy"}))
    assert core.status("claude", "10", "/x") == "working"


def test_status_claude_idle(env):
    write(env / "claude_sessions" / "10.json", json.dumps({"status": "idle"}))
    assert core.status("claude", "10", "/x") == "idle"


def test_status_claude_missing_file_falls_to_child(env):
    # No session file: fall through to the child check. "20 10 x" gives 10 a child.
    core.init(*_globals(env), "20 10 x")
    assert core.status("claude", "10", "/x") == "working"
    core.init(*_globals(env), "")
    assert core.status("claude", "10", "/x") == "idle"


def test_status_claude_bad_json_falls_to_child(env):
    write(env / "claude_sessions" / "10.json", "not json{")
    core.init(*_globals(env), "20 10 x")
    assert core.status("claude", "10", "/x") == "working"


def _copilot_events(dirpath, last):
    """Write an events.jsonl whose last turn marker is `last` (start|end)."""
    lines = ['{"assistant.turn_start": 1}', '{"assistant.turn_end": 1}']
    if last:
        lines.append('{"assistant.turn_%s": 2}' % last)
    write(dirpath / "events.jsonl", "\n".join(lines) + "\n")


def test_status_copilot_working(env):
    d = env / "copilot_state" / "s1"
    d.mkdir()
    write(d / "inuse.5.lock", "")
    _copilot_events(d, "start")
    assert core.status("copilot", "5", "/x") == "working"


def test_status_copilot_idle(env):
    d = env / "copilot_state" / "s1"
    d.mkdir()
    write(d / "inuse.5.lock", "")
    _copilot_events(d, "end")
    assert core.status("copilot", "5", "/x") == "idle"


def test_status_copilot_no_lock_unknown(env):
    assert core.status("copilot", "5", "/x") == "unknown"


def test_status_copilot_lock_but_no_events_idle(env):
    d = env / "copilot_state" / "s1"
    d.mkdir()
    write(d / "inuse.5.lock", "")
    # No events.jsonl: idle.
    assert core.status("copilot", "5", "/x") == "idle"


def test_status_pig_working_in_flight(env):
    cwd = "/work/proj"
    write(env / "pig_sessions" / "--work-proj--" / "s.jsonl",
          json.dumps({"type": "message", "message": {"role": "assistant"}}) + "\n")
    assert core.status("pig", "1", cwd) == "working"


def test_status_pig_idle_stopped(env):
    cwd = "/work/proj"
    write(env / "pig_sessions" / "--work-proj--" / "s.jsonl",
          json.dumps({"type": "message",
                      "message": {"role": "assistant", "stopReason": "stop"}}) + "\n")
    assert core.status("pig", "1", cwd) == "idle"


def test_status_pig_no_file_idle(env):
    assert core.status("pig", "1", "/nowhere") == "idle"


def test_status_pig_system_last_idle(env):
    cwd = "/work/proj"
    write(env / "pig_sessions" / "--work-proj--" / "s.jsonl",
          json.dumps({"type": "message", "message": {"role": "system"}}) + "\n")
    assert core.status("pig", "1", cwd) == "idle"


def _crush_db(cwd, finished_at):
    """Create a crush.db in cwd with one message row."""
    db = os.path.join(cwd, ".crush", "crush.db")
    os.makedirs(os.path.dirname(db), exist_ok=True)
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE messages (created_at TEXT, finished_at TEXT)")
    con.execute("INSERT INTO messages VALUES ('2026-01-01', ?)", (finished_at,))
    con.commit()
    con.close()


def test_status_crush_working(env):
    cwd = str(env / "proj")
    os.makedirs(cwd)
    _crush_db(cwd, None)
    assert core.status("crush", "1", cwd) == "working"


def test_status_crush_idle(env):
    cwd = str(env / "proj")
    os.makedirs(cwd)
    _crush_db(cwd, "2026-01-01T00:00:00")
    assert core.status("crush", "1", cwd) == "idle"


def test_status_crush_no_db_unknown(env):
    assert core.status("crush", "1", str(env / "empty")) == "unknown"


# ---------------------------------------------------------------------------
# label
# ---------------------------------------------------------------------------

def test_label_claude_user_rename(env):
    write(env / "claude_sessions" / "10.json",
          json.dumps({"name": "my rename", "nameSource": "user", "sessionId": "abc"}))
    assert core.label("claude", "10", "/x") == "my rename"


def test_label_claude_ai_title(env):
    write(env / "claude_sessions" / "10.json",
          json.dumps({"nameSource": "derived", "sessionId": "abc"}))
    # The original scans for the substring '"ai-title"' (hyphenated, quoted)
    # but reads the value from the "aiTitle" key (camelCase). The fixture line
    # must contain both for the scan to match and the read to yield a value.
    write(env / "claude_projects" / "abc.jsonl",
          '{"ai-title": "x", "aiTitle": "first"}\n'
          '{"ai-title": "y", "aiTitle": "second"}\n')
    assert core.label("claude", "10", "/x") == "second"


def test_label_claude_no_project_file_empty(env):
    write(env / "claude_sessions" / "10.json",
          json.dumps({"nameSource": "derived", "sessionId": "missing"}))
    assert core.label("claude", "10", "/x") == ""


def test_label_claude_missing_session_file_empty(env):
    # The session json itself is absent: label() must degrade to "" (no raise).
    # This is the contract the label()/ _label_impl split guarantees.
    assert core.label("claude", "999", "/x") == ""


def test_label_claude_corrupt_session_file_empty(env):
    # A session file mid-write / truncated is unreadable as json: still "".
    write(env / "claude_sessions" / "10.json", '{"nameSource": "derived", "session')
    assert core.label("claude", "10", "/x") == ""


def test_label_maki_missing_cwd_latest_empty(env):
    # cwd_latest.json absent: maki label degrades to "" (no raise).
    assert core.label("maki", "1", "/work/proj") == ""


def test_label_pi_missing_session_empty(env):
    # No pi session file at all: degrades to "" (no raise).
    assert core.label("pi", "1", "/work/proj") == ""


def test_label_maki(env):
    cwd = "/work/proj"
    write(env / "maki_sessions" / "cwd_latest.json", json.dumps({cwd: "sid1"}))
    write(env / "maki_sessions" / "sid1.jsonl",
          '{"t":"meta","title":"my session"}\n')
    assert core.label("maki", "1", cwd) == "my session"


def test_label_maki_unknown_cwd_empty(env):
    write(env / "maki_sessions" / "cwd_latest.json", json.dumps({"/other": "sid1"}))
    assert core.label("maki", "1", "/work/proj") == ""


def test_label_pi_session_info_name(env):
    cwd = "/work/proj"
    write(env / "pi_sessions" / "--work-proj--" / "s.jsonl",
          json.dumps({"type": "session_info", "name": "pi title"}) + "\n")
    assert core.label("pi", "1", cwd) == "pi title"


def test_label_pi_first_user_message(env):
    cwd = "/work/proj"
    write(env / "pi_sessions" / "--work-proj--" / "s.jsonl",
          json.dumps({"type": "message", "message": {"role": "user", "content": "hello\nworld"}}) + "\n")
    assert core.label("pi", "1", cwd) == "hello world"


def test_label_pi_long_title_truncated(env):
    cwd = "/work/proj"
    write(env / "pi_sessions" / "--work-proj--" / "s.jsonl",
          json.dumps({"type": "session_info", "name": "x" * 100}) + "\n")
    out = core.label("pi", "1", cwd)
    assert len(out) == 64
    assert out.endswith("\u2026")


def test_label_pig_uses_pig_sessions(env):
    cwd = "/work/proj"
    write(env / "pig_sessions" / "--work-proj--" / "s.jsonl",
          json.dumps({"type": "session_info", "name": "pig title"}) + "\n")
    assert core.label("pig", "1", cwd) == "pig title"


def _crush_db_with_title(cwd, title):
    db = os.path.join(cwd, ".crush", "crush.db")
    os.makedirs(os.path.dirname(db), exist_ok=True)
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE sessions (updated_at TEXT, title TEXT)")
    con.execute("INSERT INTO sessions VALUES ('2026-01-01', ?)", (title,))
    con.commit()
    con.close()


def test_label_crush_title(env):
    cwd = str(env / "proj")
    os.makedirs(cwd)
    _crush_db_with_title(cwd, "crush session")
    assert core.label("crush", "1", cwd) == "crush session"


def test_label_crush_no_db_empty(env):
    assert core.label("crush", "1", str(env / "empty")) == ""


def _copilot_store(store, sid, summary):
    con = sqlite3.connect(store)
    con.execute("CREATE TABLE sessions (id TEXT, summary TEXT)")
    con.execute("INSERT INTO sessions VALUES (?, ?)", (sid, summary))
    con.commit()
    con.close()


def test_label_copilot_summary(env):
    d = env / "copilot_state" / "s1"
    d.mkdir()
    write(d / "inuse.5.lock", "")
    _copilot_events(d, "end")
    _copilot_store(str(env / "copilot_store.db"), "s1", "copilot summary")
    assert core.label("copilot", "5", "/x") == "copilot summary"


def test_label_copilot_no_summary_short_id(env):
    d = env / "copilot_state" / "abcdef12"
    d.mkdir()
    write(d / "inuse.5.lock", "")
    _copilot_events(d, "end")
    _copilot_store(str(env / "copilot_store.db"), "abcdef12", None)
    assert core.label("copilot", "5", "/x") == "abcdef12"[:8]


def test_label_unknown_agent_empty(env):
    assert core.label("aider", "1", "/x") == ""


def test_shortest_label_picks_shortest_nonempty(env):
    """A pane can run several agents; the label is the shortest non-empty
    session name across them, so a primary with no label still shows a
    sibling's."""
    cwd = "/work/proj"
    # maki resolves to a long label, pig to a short one, claude to none.
    write(env / "maki_sessions" / "cwd_latest.json", json.dumps({cwd: "sid1"}))
    write(env / "maki_sessions" / "sid1.jsonl",
          '{"t":"meta","title":"a much longer maki session title"}\n')
    # pi/pig label: a session_info name in the pi session file, which lives at
    # <pig_sessions>/--<cwd, slashes to dashes>--/*.jsonl.
    import os
    d = env / "pig_sessions" / "--work-proj--"
    os.makedirs(d, exist_ok=True)
    write(d / "s.jsonl",
          '{"type":"session_info","name":"short"}\n')
    # pairs: claude (no label) primary, then maki (long), then pig (short).
    pairs = [("claude", "9"), ("maki", "10"), ("pig", "11")]
    assert core.shortest_label(pairs, cwd) == "short"


def test_shortest_label_empty_when_none(env):
    assert core.shortest_label([("claude", "9"), ("aider", "5")], "/x") == ""


def test_shortest_label_single(env):
    cwd = "/work/proj"
    write(env / "maki_sessions" / "cwd_latest.json", json.dumps({cwd: "sid1"}))
    write(env / "maki_sessions" / "sid1.jsonl",
          '{"t":"meta","title":"only one"}\n')
    assert core.shortest_label([("maki", "10")], cwd) == "only one"


def test_reduce_status_any_working_wins():
    # A pane is blue if ANY agent is working, even if others are idle/unknown.
    assert core.reduce_status(["idle", "working", "idle"]) == "working"
    assert core.reduce_status(["working", "unknown"]) == "working"
    assert core.reduce_status(["unknown", "working"]) == "working"


def test_reduce_status_all_idle_is_idle():
    # No working: idle if any agent is known-idle.
    assert core.reduce_status(["idle", "idle"]) == "idle"
    assert core.reduce_status(["unknown", "idle"]) == "idle"


def test_reduce_status_all_unknown_is_unknown():
    # Only unknowns (or none): unknown.
    assert core.reduce_status(["unknown", "unknown"]) == "unknown"
    assert core.reduce_status([]) == "unknown"


def test_reduce_status_single():
    assert core.reduce_status(["working"]) == "working"
    assert core.reduce_status(["idle"]) == "idle"
    assert core.reduce_status(["unknown"]) == "unknown"


# ---------------------------------------------------------------------------
# cli end-to-end
# ---------------------------------------------------------------------------

def test_cli_stdin_stdout_contract(env, capsys):
    """Feed cli.main pane lines and check the status US label output.

    The stdin contract is pane TAB <name1 pid1 name2 pid2 ...> TAB cwd: the
    pairs carry every agent so the label is the shortest non-empty session
    name across them, while status/icon use the primary (first) pair.
    """
    import io
    cwd = "/work/proj"
    write(env / "maki_sessions" / "cwd_latest.json", json.dumps({cwd: "sid1"}))
    write(env / "maki_sessions" / "sid1.jsonl",
          '{"t":"meta","title":"maki label"}\n')

    sys.stdin = io.StringIO(
        "\t".join(["%1", "maki 9", cwd]) + "\n" +
        "\t".join(["%2", "", ""]) + "\n" +
        "\t".join(["%3", "aider 4", "/x"]) + "\n"
    )
    cli.main(_globals(env) + ("",))
    out = capsys.readouterr().out
    lines = out.splitlines()
    assert len(lines) == 3
    # maki: no children in snap (empty), so idle; label present.
    st, lb = lines[0].split("\037")
    assert st == "idle"
    assert lb == "maki label"
    # agent-less pane: empty status, empty label.
    assert lines[1] == "\037"
    # aider: unknown agent, child check (no kids) -> idle, no label.
    st, lb = lines[2].split("\037")
    assert st == "idle"
    assert lb == ""
