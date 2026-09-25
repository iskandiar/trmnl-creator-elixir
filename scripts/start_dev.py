#!/usr/bin/env python3
"""Start the development server with a Google web-client JSON, without shell evaluation."""
import argparse
import json
import os
from pathlib import Path
import sys


def environment(path, port):
    env = os.environ.copy()
    env["PORT"] = str(port)
    env.setdefault("GOOGLE_REDIRECT_URI", f"http://localhost:{port}/oauth/callback")
    if path:
        try:
            data = json.loads(Path(path).expanduser().read_text())
            client = data["web"]
            for name in ("client_id", "client_secret"):
                if not isinstance(client.get(name), str) or not client[name].strip():
                    raise ValueError()
            redirects = client.get("redirect_uris", [])
            if redirects and env["GOOGLE_REDIRECT_URI"] not in redirects:
                raise RuntimeError("Add the callback URL shown below to the client's authorized redirect URIs, then download its JSON again.")
            env["GOOGLE_CLIENT_ID"] = client["client_id"]
            env["GOOGLE_CLIENT_SECRET"] = client["client_secret"]
        except (OSError, ValueError, KeyError, TypeError):
            raise RuntimeError("Cannot load Google credentials. Use a JSON downloaded for a Web application OAuth client.") from None
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "4010")))
    parser.add_argument("--google-client-json", default=".tmp/google-oauth.json" if Path(".tmp/google-oauth.json").exists() else None)
    parser.add_argument("--check", action="store_true", help="Validate configuration without starting the server")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("Port must be between 1 and 65535")
    try:
        env = environment(args.google_client_json, args.port)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        print("Callback: " + os.environ.get("GOOGLE_REDIRECT_URI", f"http://localhost:{args.port}/oauth/callback"), file=sys.stderr)
        return 1
    configured = all(env.get(k, "").strip() for k in ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"))
    print(f"Dashboard: http://localhost:{args.port}", flush=True)
    print("Google OAuth: " + ("configured" if configured else "not configured — see docs/GOOGLE_SETUP.md"), flush=True)
    print("Callback: " + env["GOOGLE_REDIRECT_URI"], flush=True)
    if not args.check:
        os.execvpe("mix", ["mix", "phx.server"], env)
    return 0


if __name__ == "__main__":
    sys.exit(main())
