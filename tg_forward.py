import os
from telethon import TelegramClient, events
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

API_ID = int(os.getenv("TG_API_ID"))
API_HASH = os.getenv("TG_API_HASH")
SOURCE = os.getenv("TG_SOURCE")
DEST = os.getenv("TG_DEST")

if not all([API_ID, API_HASH, SOURCE, DEST]):
    raise RuntimeError("Missing required environment variables")

client = TelegramClient("session", API_ID, API_HASH)

@client.on(events.NewMessage(chats=SOURCE))
async def handler(event):
    await client.send_message(DEST, event.message)

client.start()
print("Listening...")
client.run_until_disconnected()
