#!/usr/bin/env python3

import os
from pathlib import Path

from dotenv import load_dotenv
from telethon import TelegramClient, events

# ------------------------------------------------------------
# Load configuration
# ------------------------------------------------------------
load_dotenv(Path(__file__).with_name(".env"))

API_ID = int(os.getenv("TG_API_ID"))
API_HASH = os.getenv("TG_API_HASH")
SOURCE = os.getenv("TG_SOURCE")
DEST = os.getenv("TG_DEST")

if not API_ID or not API_HASH or not SOURCE or not DEST:
    raise RuntimeError(
        "Missing TG_API_ID, TG_API_HASH, TG_SOURCE or TG_DEST in .env"
    )

# Convert numeric IDs to integers
try:
    SOURCE = int(SOURCE)
except ValueError:
    pass

try:
    DEST = int(DEST)
except ValueError:
    pass

# ------------------------------------------------------------
# Telegram Client
# ------------------------------------------------------------
client = TelegramClient("session", API_ID, API_HASH)


@client.on(events.NewMessage(chats=SOURCE))
async def handler(event):
    print(f"Received message {event.id}")

    try:
        await event.forward_to(DEST)
        print(f"✅ Forwarded message {event.id} to {DEST}")
    except Exception:
        import traceback
        traceback.print_exc()

def main():
    print("Connecting to Telegram...")

    client.start()

    me = client.loop.run_until_complete(client.get_me())

    print("----------------------------------------")
    print("Telegram Forwarder Started")
    print("----------------------------------------")
    print(f"Logged in as : {me.first_name}")
    print(f"My ID        : {me.id}")
    print(f"Source Chat  : {SOURCE}")
    print(f"Destination  : {DEST}")
    print("----------------------------------------")
    print("Waiting for messages...")
    print("----------------------------------------")

    client.run_until_disconnected()

if __name__ == "__main__":
    main()