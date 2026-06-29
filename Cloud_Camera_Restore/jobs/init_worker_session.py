#!/usr/bin/env python3

import asyncio
import shutil
from pathlib import Path

from telethon import TelegramClient
from rich.console import Console


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent


def load_env(path):
    env = {}

    with open(path) as f:
        for line in f:
            line = line.strip()

            if not line or line.startswith("#"):
                continue

            key, value = line.split("=", 1)
            env[key.strip()] = value.strip().strip('"').strip("'")

    return env


config = load_env(PROJECT_ROOT / "env" / "telegram_app.env")
target = load_env(PROJECT_ROOT / "conf" / "restore_target.conf")

API_ID = int(config["API_ID"])
API_HASH = config["API_HASH"]

WORKERS = int(target.get("DOWNLOAD_WORKERS", 30))

console = Console()

SESSION_DIR = PROJECT_ROOT / "sessions"
MASTER_SESSION = SESSION_DIR / "master.session"


async def main():

    if not MASTER_SESSION.exists():
        console.print("[red]master.session not found.[/red]")
        console.print("Run init_master_session.py first.")
        return

    client = TelegramClient(
        str(MASTER_SESSION.with_suffix("")),
        API_ID,
        API_HASH,
    )

    await client.connect()

    if not await client.is_user_authorized():
        console.print("[red]master.session is not authorized.[/red]")
        console.print("Run init_master_session.py again.")
        await client.disconnect()
        return

    me = await client.get_me()

    console.print(f"Logged in as: [green]{me.first_name}[/green]")
    console.print(f"Creating {WORKERS} worker session(s)...")
    console.print()

    await client.disconnect()

    #
    # Remove old worker sessions
    #

    for file in SESSION_DIR.glob("restore*.session"):
        file.unlink()

    created = 0

    #
    # Copy master session
    #

    for i in range(1, WORKERS + 1):

        worker = SESSION_DIR / f"restore{i:02d}.session"

        shutil.copy2(MASTER_SESSION, worker)

        created += 1

    console.print(
        f"[green]Created {created} worker sessions.[/green]"
    )


if __name__ == "__main__":
    asyncio.run(main())