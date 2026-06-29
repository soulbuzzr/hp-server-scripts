#!/usr/bin/env python3

import sys
import shutil
import asyncio
from asyncio import Queue, QueueEmpty
from datetime import datetime, timedelta, timezone
from pathlib import Path
from telethon import TelegramClient
from rich.console import Console
from rich.progress import (
    Progress,
    BarColumn,
    TextColumn,
    DownloadColumn,
    TransferSpeedColumn,
    TimeElapsedColumn,
    TaskProgressColumn,
)

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

config = load_env(PROJECT_ROOT/"env/telegram_app.env")

API_ID = int(config["API_ID"])
API_HASH = config["API_HASH"]

CHAT = "Main Camera Recording"

target = load_env(PROJECT_ROOT/"conf/restore_target.conf")

if len(sys.argv) != 3:
    print(f"Usage: {Path(sys.argv[0]).name} <date YYYY-MM-DD> <hour (00-23)>")
    sys.exit(1)

DATE = sys.argv[1]

try:
    datetime.strptime(DATE, "%Y-%m-%d")
except ValueError:
    print("Error: date must be in YYYY-MM-DD format.")
    sys.exit(1)

try:
    HOUR = int(sys.argv[2])
except ValueError:
    print("Error: hour must be an integer between 00 and 23.")
    sys.exit(1)

if not (0 <= HOUR <= 23):
    print("Error: hour must be between 00 and 23.")
    sys.exit(1)

DOWNLOAD = {
    "camera": target["camera"],
    "date": DATE,
    "hour": HOUR,
    "hour_dir": f"{HOUR:02d}-{HOUR+1:02d}",
}

DOWNLOAD_WORKERS = int(target["DOWNLOAD_WORKERS"])

SEARCH_MARGIN = timedelta(minutes=30)

download_root = Path(target["DOWNLOAD_DIR"])

if not download_root.is_absolute():
    raise ValueError(
        "Downlod directory in restore_target.conf must be an absolute path"
    )

DOWNLOAD_DIR = (
    download_root   
    / DOWNLOAD["camera"]
    / DOWNLOAD["date"]
    / DOWNLOAD["hour_dir"]
    / "raw"
)

DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

console = Console()

overall_bytes = 0
overall_lock = asyncio.Lock()

progress_display = Progress(
    TextColumn("[bold cyan]{task.fields[worker]}"),
    TextColumn("{task.fields[file]}"),
    BarColumn(
        complete_style="green",
        finished_style="bright_green",
        pulse_style="yellow",
    ),
    TaskProgressColumn(),
    TextColumn("{task.fields[extra]}"),
    TimeElapsedColumn(),
)

def progress_callback(task_id):

    def callback(current, total):

        progress_display.update(
            task_id,
            completed=current,
            extra=f"{current/1024/1024:.1f}/{total/1024/1024:.1f} MB",
        )

    return callback

def update_overall(overall_task, bytes_done):

    task = progress_display.tasks[overall_task]

    progress_display.update(
        overall_task,
        completed=bytes_done,
        file=f"{task.fields['files_done']}/{task.fields['files_total']} files",
        extra=f"{bytes_done/1024/1024:.1f}/{task.total/1024/1024:.1f} MB",
    )

async def download_worker(
    worker_name,
    task_id,
    overall_task,
    client,
    queue,
):
    
    global overall_bytes

    while True:

        try:
            msg = queue.get_nowait()

        except QueueEmpty:
            break

        filename = msg.file.name
        destination = DOWNLOAD_DIR / filename

        if destination.exists():

            progress_display.update(
                task_id,
                worker=worker_name,
                file=f"✓ {filename} (cached)",
                total=1,
                completed=1,
            )

            async with overall_lock:
                overall_bytes += msg.file.size

                progress_display.tasks[overall_task].fields["files_done"] += 1

                progress_display.advance(overall_task, msg.file.size)

                update_overall(overall_task, overall_bytes)

            continue

        progress_display.reset(task_id)

        progress_display.update(
            task_id,
            worker=worker_name,
            file=filename,
            extra="",
            total=msg.file.size,
            completed=0,
        )

        try:
            await client.download_media(
                msg,
                file=str(destination),
                progress_callback=progress_callback(task_id),      
                )
        except Exception as e:
            progress_display.update(
                task_id,
                file=f"✗ {filename}",
            )

            console.print(f"[red]{e}[/red]")
            continue

        progress_display.update(
            task_id,
            completed=msg.file.size,
            file=f"✓ {filename}",
        )

        async with overall_lock:
            overall_bytes += msg.file.size

            progress_display.tasks[overall_task].fields["files_done"] += 1

            progress_display.advance(overall_task, msg.file.size)

            update_overall(overall_task, overall_bytes)

async def main():

    SESSION_DIR = PROJECT_ROOT / "sessions"
    MASTER_SESSION = SESSION_DIR / "master.session"

    if not MASTER_SESSION.exists():
        raise RuntimeError("master.session not found.")

    #
    # Reinitialize worker sessions
    #

    for file in SESSION_DIR.glob("restore*.session"):
        file.unlink()

    for i in range(1, DOWNLOAD_WORKERS + 1):
        shutil.copy2(
            MASTER_SESSION,
            SESSION_DIR / f"restore{i:02d}.session",
        )
        
    sessions = sorted(
        (PROJECT_ROOT/"sessions").glob("restore*.session")
    )

    if len(sessions) < DOWNLOAD_WORKERS:
        raise RuntimeError(
            f"Configured DOWNLOAD_WORKERS={DOWNLOAD_WORKERS}, "
            f"but only {len(sessions)} worker sessions exist."
        )

    sessions = sessions[:DOWNLOAD_WORKERS]

    if not sessions:
        console.print("No restore sessions found.")
        return

    console.print(
        f"Hour {HOUR:02d}: Found {len(sessions)} worker session(s)"
    )
    console.print()

    search_session = sessions[0]

    console.print(f"Searching Telegram for hour's recordings...")
    console.print()

    prefix = (
        f"{DOWNLOAD['camera']}_"
        f"{DOWNLOAD['date']}_"
        f"{DOWNLOAD['hour']:02d}-"
    )

    search_client = TelegramClient(
        str(search_session.with_suffix("")),
        API_ID,
        API_HASH,
    )

    await search_client.start()

    ist = timezone(timedelta(hours=5, minutes=30))

    start_ist = datetime.strptime(
        f"{DOWNLOAD['date']} {DOWNLOAD['hour']:02d}:00:00",
        "%Y-%m-%d %H:%M:%S",
    ).replace(tzinfo=ist)

    end_ist = start_ist + timedelta(hours=1)

    start_utc = start_ist.astimezone(timezone.utc)
    end_utc = end_ist.astimezone(timezone.utc)

    search_start = start_utc - SEARCH_MARGIN
    search_end = end_utc + SEARCH_MARGIN

    console.print("Searching Telegram...")
    console.print(f"Camera         : {DOWNLOAD['camera']}")
    console.print(f"Date           : {DOWNLOAD['date']}")
    console.print(f"Hour           : {DOWNLOAD['hour_dir']}")
    console.print(f"Filename Match : {prefix}")

    console.print(
        "Requested Hour : "
        f"{start_ist.strftime('%Y-%m-%d %H:%M:%S IST')} -> "
        f"{end_ist.strftime('%Y-%m-%d %H:%M:%S IST')}"
    )

    console.print(
        "Search Window  : "
        f"{(start_ist - SEARCH_MARGIN).strftime('%Y-%m-%d %H:%M:%S IST')} -> "
        f"{(end_ist + SEARCH_MARGIN).strftime('%Y-%m-%d %H:%M:%S IST')}"
    )

    console.print(f"Download Dir   : {DOWNLOAD_DIR}")
    console.print()

    matches = []
    scanned = 0

    async for msg in search_client.iter_messages(
        CHAT,
        offset_date=search_end,
    ):

        scanned += 1

        if msg.date < search_start:
            break

        if not msg.file:
            continue

        filename = msg.file.name

        if not filename:
            continue

        if filename.startswith(prefix):
            matches.append(msg)

    matches.sort(key=lambda m: m.file.name)

    total_bytes = sum(msg.file.size for msg in matches)

    queue = Queue()

    for msg in matches:
        await queue.put(msg)

    console.print(f"Scanned {scanned} messages")
    console.print(f"Found   {len(matches)} recordings\n")

    console.print("-" * 70)

    for index, msg in enumerate(matches, start=1):
        console.print(f"{index:02d}. {msg.file.name}")

    console.print("-" * 70)
    console.print()

    await search_client.disconnect()

    download_clients = [
        TelegramClient(
            str(session.with_suffix("")),
            API_ID,
            API_HASH,
        )
        for session in sessions
    ]
    console.print(f"Connecting {len(download_clients)} download workers...\n")

    await asyncio.gather(
        *(client.start() for client in download_clients)
    )
      
    console.print("Beginning download...\n")

    worker_tasks = {}

    overall_task = progress_display.add_task(
        "",
        worker="[bold green]ALL",
        file=f"0/{len(matches)} files",
        extra=f"0.0/{total_bytes/1024/1024:.1f} MB",
        total=total_bytes,
        files_done=0,
        files_total=len(matches),
    )

    for i in range(1, len(download_clients)+1):

        worker_tasks[f"W{i}"] = progress_display.add_task(
            "",
            worker=f"W{i}",
            file="Waiting...",
            extra="",
            total=1,            
        )

    tasks = []

    for i, client in enumerate(download_clients, start=1):
        tasks.append(
            asyncio.create_task(
                download_worker(
                    f"W{i}",
                    worker_tasks[f"W{i}"],
                    overall_task,
                    client,
                    queue,
                )
            )
        )   

    with progress_display:

        await asyncio.gather(*tasks)

    # Disconnect download clients
    for client in download_clients:
        await client.disconnect()

    console.print("\nDownload stage complete.")
    console.print(f"Files stored in:\n{DOWNLOAD_DIR}")


if __name__ == "__main__":
    asyncio.run(main())
