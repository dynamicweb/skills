#!/usr/bin/env python3
"""READ-ONLY. Find precedent on the dynamicweb/DynamicWeb issue tracker before posting.

Searches issues (title, body and comments) for the given words through the gh CLI, then
prints each hit with its state, labels and the maintainer's own replies, so a draft can be
checked against earlier rulings ("We will not do this", "You can already ...", a work item
in progress) before it is posted. Writes nothing anywhere.

Owning reference: ../references/maintainer-patterns.md ("Standing refusals and constraints").

Traps encoded:
- GitHub search matches comments as well as the post, so a hit may be a thread where the
  words appear only in a reply; the maintainer's replies are printed so that is visible.
- The gh CLI must be signed in (`gh auth status`); an unauthenticated call returns an error,
  never an empty list, and this script fails loudly in that case.
- Output is UTF-8 regardless of the console code page.

Requires: Python 3.12+ and the gh CLI on PATH. No third-party packages.

Parameters:
  --search WORDS       words to search for (required); quote a phrase
  --repo OWNER/NAME    tracker to search (default dynamicweb/DynamicWeb)
  --maintainer LOGIN   GitHub login whose replies are printed (default nicped)
  --limit N            maximum issues to fetch (default 30)
  --rejected-only      keep only issues labelled Rejected or Waiting for more votes,
                       or whose maintainer reply contains a refusal phrase

Examples:
  python3 find_precedent.py --search "access denied"
  python3 find_precedent.py --search impersonation --rejected-only
  python3 find_precedent.py --search "sort column" --limit 20

Exit code 0 on success (also when nothing matches), 1 when gh fails.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

REFUSAL = re.compile(
    r"we will not|will not happen|not a priority|by design|completely off|"
    r"cannot implement|do not agree|i do not think we will|too big",
    re.IGNORECASE,
)


def run_gh(args: list[str]) -> str:
    try:
        result = subprocess.run(
            ["gh", *args], capture_output=True, text=True, encoding="utf-8", check=False
        )
    except FileNotFoundError:
        sys.exit("gh CLI not found on PATH. Install it and run `gh auth login`.")
    if result.returncode != 0:
        sys.exit(f"gh failed: {result.stderr.strip() or 'no error text'}. Check `gh auth status`.")
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--search", required=True, help="words to search for")
    parser.add_argument("--repo", default="dynamicweb/DynamicWeb")
    parser.add_argument("--maintainer", default="nicped")
    parser.add_argument("--limit", type=int, default=30)
    parser.add_argument("--rejected-only", action="store_true")
    opts = parser.parse_args()

    sys.stdout.reconfigure(encoding="utf-8")

    issues = json.loads(
        run_gh(
            [
                "issue", "list", "--repo", opts.repo, "--state", "all",
                "--search", opts.search, "--limit", str(opts.limit),
                "--json", "number,title,state,labels,url,createdAt",
            ]
        )
    )
    if not issues:
        print(f"No issues match '{opts.search}' in {opts.repo}.")
        return 0

    shown = 0
    for issue in sorted(issues, key=lambda i: i["number"], reverse=True):
        labels = [label["name"] for label in issue["labels"]]
        comments = json.loads(
            run_gh(["api", f"repos/{opts.repo}/issues/{issue['number']}/comments", "--paginate"])
        )
        replies = [
            c for c in comments if c.get("user", {}).get("login", "").lower() == opts.maintainer.lower()
        ]
        refused = any(label in ("Rejected", "Waiting for more votes") for label in labels) or any(
            REFUSAL.search(c.get("body") or "") for c in replies
        )
        if opts.rejected_only and not refused:
            continue
        shown += 1
        print(f"#{issue['number']} [{issue['state']}] {issue['title']}")
        print(f"  labels: {', '.join(labels) or 'none'}   {issue['url']}")
        if not replies:
            print(f"  no reply from {opts.maintainer}")
        for reply in replies:
            text = re.sub(r"\s+", " ", (reply.get("body") or "").strip())
            print(f"  {opts.maintainer} ({reply['created_at'][:10]}): {text[:600]}")
        print()

    print(f"{shown} of {len(issues)} fetched issues shown.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
