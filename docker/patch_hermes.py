#!/usr/bin/env python3
"""
Patch Hermes-Agent v0.13.x (release tag v2026.5.7) so that /model
picks survive the /new (/reset) command.

Upstream bug:
  In gateway/run.py's _handle_reset_command, the /new (/reset) command
  wipes `_session_model_overrides[session_key]`, the reasoning override,
  and any pending model note. Telegram users naturally do:
      /new   (start a fresh conversation)
      /model (pick a model)
      ... message ...
  …and then to start ANOTHER fresh chat they do /new again, which
  silently reverts the active model back to HERMES_DEFAULT_PROVIDER /
  HERMES_DEFAULT_MODEL. The /model picker still says "switched" but the
  next message hits the configured default.

Fix:
  Comment out the four-line block that pops the model/reasoning overrides
  on session reset. We deliberately leave the OTHER two override-clearing
  paths intact (was_auto_reset and compression_exhausted branches) —
  those are genuine "the agent fell over" recoveries and should reset
  to a safe default. Only the explicit /new no longer wipes the user's
  picked model.

Applied at Docker-build time, immediately after pip installs hermes-agent.
Idempotent: re-running on an already-patched file is a no-op.
"""
import re
import sys
from pathlib import Path

MARKER = "# HERMES-PATCH: /model survives /new"

PATTERN = re.compile(
    r"(\n        # Clear any session-scoped model/reasoning overrides so the next agent\n"
    r"        # picks up configured defaults instead of previous session switches\.\n)"
    r"(        self\._session_model_overrides\.pop\(session_key, None\)\n"
    r"        self\._set_session_reasoning_override\(session_key, None\)\n"
    r"        if hasattr\(self, \"_pending_model_notes\"\):\n"
    r"            self\._pending_model_notes\.pop\(session_key, None\)\n)"
)

REPLACEMENT_BLOCK = (
    "\n"
    "        " + MARKER + "\n"
    "        # Upstream wipes the picked model on /new, which makes /model\n"
    "        # selections silently revert to HERMES_DEFAULT_*. We preserve\n"
    "        # the override across /new so users can pick a model once and\n"
    "        # keep using it across fresh conversations. To restore upstream\n"
    "        # behavior, uncomment the four lines below.\n"
    "        # self._session_model_overrides.pop(session_key, None)\n"
    "        # self._set_session_reasoning_override(session_key, None)\n"
    "        # if hasattr(self, \"_pending_model_notes\"):\n"
    "        #     self._pending_model_notes.pop(session_key, None)\n"
)


def patch(path: Path) -> bool:
    src = path.read_text()
    if MARKER in src:
        print(f"[patch_hermes] already patched: {path}")
        return True
    new_src, n = PATTERN.subn(lambda m: REPLACEMENT_BLOCK, src, count=1)
    if n == 0:
        print(f"[patch_hermes] ERROR: pattern not found in {path}", file=sys.stderr)
        return False
    path.write_text(new_src)
    print(f"[patch_hermes] patched {path}")
    return True


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: patch_hermes.py <path-to-site-packages>", file=sys.stderr)
        return 2
    site_pkgs = Path(sys.argv[1])
    run_py = site_pkgs / "gateway" / "run.py"
    if not run_py.exists():
        print(f"[patch_hermes] ERROR: {run_py} does not exist", file=sys.stderr)
        return 2
    return 0 if patch(run_py) else 1


if __name__ == "__main__":
    sys.exit(main())
