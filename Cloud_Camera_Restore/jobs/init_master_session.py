#!/usr/bin/env python3

import asyncio
from pathlib import Path

from telethon import TelegramClient
from rich.console import Console
from rich.table import Table


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

API_ID = int(config["API_ID"])
API_HASH = config["API_HASH"]

SESSION_DIR = PROJECT_ROOT / "sessions"
SESSION_DIR.mkdir(parents=True, exist_ok=True)

SESSION_FILE = SESSION_DIR / "master.session"

console = Console()


async def main():

    client = TelegramClient(
        str(SESSION_FILE.with_suffix("")),
        API_ID,
        API_HASH,
    )

    await client.start()

    me = await client.get_me()

    console.print()
    console.print("[bold green]Master session initialized[/bold green]")
    console.print(f"Name     : {me.first_name}")
    console.print(f"Username : @{me.username}" if me.username else "Username : -")
    console.print(f"Phone    : {me.phone}")
    console.print()

    table = Table(title="Telegram Chats")

    table.add_column("#", justify="right")
    table.add_column("Type")
    table.add_column("Name")
    table.add_column("Chat ID", justify="right")

    index = 1

    async for dialog in client.iter_dialogs():

        if dialog.is_user:
            kind = "User"
        elif dialog.is_group:
            kind = "Group"
        elif dialog.is_channel:
            kind = "Channel"
        else:
            kind = "Other"

        table.add_row(
            str(index),
            kind,
            dialog.name,
            str(dialog.id),
        )

        index += 1

    console.print(table)

    await client.disconnect()

    console.print()
    console.print(f"[green]Master session saved to[/green]")
    console.print(f"{SESSION_FILE}")


if __name__ == "__main__":
    asyncio.run(main())