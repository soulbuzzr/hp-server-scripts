#!/usr/bin/env python3

import os
from pathlib import Path

from dotenv import load_dotenv
from telethon import TelegramClient, events

# Load .env from the same directory as this script
load_dotenv(Path(__file__).with_name(".env"))

API_ID = os.getenv("TG_API_ID")
API_HASH = os.getenv("TG_API_HASH")
SOURCE = os.getenv("TG_SOURCE")
DEST = os.getenv("TG_DEST")

if not API_ID or not API_HASH or not SOURCE or not DEST:
    raise RuntimeError(
        "Missing one or more required variables: "
        "TG_API_ID, TG_API_HASH, TG_SOURCE, TG_DEST"
    )

API_ID = int(API_ID)

# Convert numeric IDs to int, leave usernames/"me" as strings
try:
    SOURCE = int(SOURCE)
except ValueError:
    pass

try:
    DEST = int(DEST)
except ValueError:
    pass

client = TelegramClient("session", API_ID, API_HASH)


@client.on(events.NewMessage(chats=SOURCE))
async def forward_message(event):
    try:
        await event.forward_to(DEST)

        sender = await event.get_sender()
        sender_name = getattr(sender, "first_name", None) or getattr(sender, "title", None) or "Unknown"

        print(
            f"[OK] Forwarded message {event.id} "
            f"from {sender_name}"
        )

    except Exception as e:
        print(f"[ERROR] Failed to forward message {event.id}: {e}")


def main():
    client.start()

    print("======================================")
    print(" Telegram Forwarder Started")
    print(f" Source      : {SOURCE}")
    print(f" Destination : {DEST}")
    print(" Waiting for new messages...")
    print("======================================")

    client.run_until_disconnected()


if __name__ == "__main__":
    main()