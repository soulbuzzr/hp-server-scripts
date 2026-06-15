from flask import Flask, Response, jsonify, render_template_string
import subprocess
import os
import logging
import time
import json

NETWORK_INTERFACE = "enp0s25"
IMMICH_COMPOSE_DIR = "/home/hpserver/immich-app"
MAIN_CAMERA_IP = "192.168.1.200"
MINI_CAMERA_IP = "192.168.1.201"

RECORDING_AGE_LIMIT = 300

CAMERA_RECORDINGS = {
    "main": "/home/hpserver/Ramdisk/Camera_Recording/main",
    "mini": "/home/hpserver/Ramdisk/Camera_Recording/mini"
}

_disk_prev = {}
_disk_map = None

_last_rx = None
_last_tx = None
_last_net_time = None

_last_ts_rx = None
_last_ts_tx = None
_last_ts_time = None

app = Flask(__name__)

log = logging.getLogger("werkzeug")
log.setLevel(logging.ERROR)

_last_idle = None
_last_total = None
_last_cpu = 0.0

_core_prev = {}

HTML = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Home Server</title>

<style>
body {
    background: #0f1117;
    color: #fff;
    font-family: Inter, Arial, sans-serif;
    margin: 0;
    padding: 30px;
}

h1 {
    margin-bottom: 25px;
}

.grid {
    display: grid;
    grid-template-columns: repeat(auto-fit,minmax(250px,1fr));
    gap: 20px;
}

.card {
    background: #1a1d29;
    border-radius: 16px;
    padding: 20px;
    box-shadow: 0 0 15px rgba(0,0,0,.3);
}

.label {
    color: #999;
    font-size: 14px;
}

.value {
    margin-top: 10px;
    font-size: 32px;
    font-weight: bold;
}

.small {
    margin-top: 10px;
    color: #bbb;
}

.core {
    margin-top: 8px;
    font-size: 14px;
    font-weight: bold;
}

.green {
    color: #4ade80;
}

.yellow {
    color: #facc15;
}

.red {
    color: #ef4444;
}

.status-good {
    color: #4ade80;
    font-weight: bold;
}

.status-bad {
    color: #ef4444;
    font-weight: bold;
}

.disk-read {
    margin-top: 10px;
    font-size: 15px;
    font-weight: 700;
    font-style: italic;
    color: #60a5fa;
}

.disk-write {
    margin-top: 3px;
    font-size: 15px;
    font-weight: 700;
    font-style: italic;
    color: #f59e0b;
}
</style>
</head>

<body>

<h1>🏠 Home Server</h1>

<div class="grid">

<div class="card">
<div class="label">CPU Usage</div>
<div id="cpu" class="value">--</div>
</div>

<div class="card">
<div class="label">CPU Temperature</div>
<div id="temp" class="value">--</div>
</div>

<div class="card">
<div class="label">GPU Temperature</div>
<div id="gpu_temp" class="value">--</div>
</div>

<div class="card">
<div class="label">RAM Usage</div>
<div id="ram" class="value">--</div>
</div>

<div class="card">
<div class="label">Uptime</div>
<div id="uptime" class="small">--</div>
</div>

<div class="card">
<div class="label">Immich Status</div>
<div id="immich" class="small">--</div>
</div>

<div class="card">
<div class="label">Network In</div>
<div id="net_in" class="value">--</div>
</div>

<div class="card">
<div class="label">Network Out</div>
<div id="net_out" class="value">--</div>
</div>

<div class="card">
<div class="label">Tailscale In</div>
<div id="ts_in" class="value">--</div>
</div>

<div class="card">
<div class="label">Tailscale Out</div>
<div id="ts_out" class="value">--</div>
</div>

<div class="card">
<div class="label">Main Camera</div>
<div id="main_camera" class="small">--</div>
</div>

<div class="card">
<div class="label">Mini Camera</div>
<div id="mini_camera" class="small">--</div>
</div>

<div class="card">
<div class="label">Boot SSD</div>
<div id="boot_ssd" class="value">--</div>
</div>

<div class="card">
<div class="label">Multimedia SSD</div>
<div id="multimedia_ssd" class="value">--</div>
</div>

<div class="card">
<div class="label">Camera HDD</div>
<div id="camera_hdd" class="value">--</div>
</div>

<div class="card">
<div class="label">Data HDD</div>
<div id="data_hdd" class="value">--</div>
</div>

<div class="card">
<div class="label">CPU Cores</div>
<div id="cores" class="small">--</div>
</div>

</div>

<script>

function getColorClass(value) {

    if (value < 40)
        return "green";

    if (value < 80)
        return "yellow";

    return "red";
}

function getTempColorClass(value) {

    if (value < 60)
        return "green";

    if (value < 75)
        return "yellow";

    return "red";
}

function getDiskColorClass(value) {

    if (value < 60)
        return "green";

    if (value < 85)
        return "yellow";

    return "red";
}

function updateDrive(id, data) {

    const el = document.getElementById(id);

    el.innerHTML =
        data.percent + "%<br>" +

        "<span style='font-size:14px'>" +
        data.used_gb + " GB used / " +
        data.free_gb + " GB free" +
        "</span>" +

        "<div class='disk-read'>" +
        "Disk Read: " +
        formatDiskRate(data.read_mbps ?? 0) +
        "</div>" +

        "<div class='disk-write'>" +
        "Disk Write: " +
        formatDiskRate(data.write_mbps ?? 0) +
        "</div>";

    el.className =
        "value " + getDiskColorClass(data.percent);
}

function formatRate(bps) {

    if (bps < 1000)
        return bps + " bps";

    if (bps < 1000000)
        return (bps / 1000).toFixed(1) + " Kbps";

    return (bps / 1000000).toFixed(1) + " Mbps";
}

function formatDiskRate(mbps) {

    const bps = mbps * 1024 * 1024;

    if (bps < 1024)
        return bps.toFixed(0) + " B/s";

    if (bps < 1024 * 1024)
        return (bps / 1024).toFixed(1) + " KB/s";

    if (bps < 1024 * 1024 * 1024)
        return (bps / 1024 / 1024).toFixed(1) + " MB/s";

    return (bps / 1024 / 1024 / 1024).toFixed(1) + " GB/s";
}

function cameraHtml(data) {

    const liveClass =
        data.live ? "green" : "red";

    const recClass =
        data.recording ? "green" : "red";

    return `
        <div class="status-row">
            LIVE:
            <span class="${liveClass}">●</span>
        </div>

        <div class="status-row">
            RECORDING:
            <span class="${recClass}">●</span>
        </div>

        <div style="margin-top:8px">
            Last File:<br>
            ${data.last_file || "N/A"}
        </div>
    `;
}

async function updateStats() {

    const r = await fetch('/api/stats');
    const d = await r.json();

    const cpuEl = document.getElementById("cpu");

    cpuEl.textContent = d.cpu + "%";
    cpuEl.className = "value " + getColorClass(d.cpu);

    const tempEl = document.getElementById("temp");

    tempEl.textContent = d.temp + "°C";
    tempEl.className = "value " + getTempColorClass(d.temp);

    const gpuTempEl = document.getElementById("gpu_temp");

    gpuTempEl.textContent = d.gpu_temp + "°C";
    gpuTempEl.className = "value " + getTempColorClass(d.gpu_temp);

    const ramEl = document.getElementById("ram");

    ramEl.innerHTML =
        d.ram.percent + "%<br>" +
        "<span style='font-size:14px'>" +
        d.ram.used_gb + " GB used / " +
        d.ram.free_gb + " GB free" +
        "</span>";

    ramEl.className =
        "value " + getColorClass(d.ram.percent);

    updateDrive(
        "boot_ssd",
        {
            ...d.storage.boot_ssd,
            ...d.disk_activity.boot_ssd
        }
    );

    updateDrive(
        "multimedia_ssd",
        {
            ...d.storage.multimedia_ssd,
            ...d.disk_activity.multimedia_ssd
        }
    );

    updateDrive(
        "camera_hdd",
        {
            ...d.storage.camera_hdd,
            ...d.disk_activity.camera_hdd
        }
    );

    updateDrive(
        "data_hdd",
        {
            ...d.storage.data_hdd,
            ...d.disk_activity.data_hdd
        }
    );

    document.getElementById("net_in").textContent =
        formatRate(d.network.rx_bps);

    document.getElementById("net_out").textContent =
        formatRate(d.network.tx_bps);

    document.getElementById("ts_in").textContent =
        formatRate(d.tailscale.rx_bps);

    document.getElementById("ts_out").textContent =
        formatRate(d.tailscale.tx_bps);

    document.getElementById("uptime").textContent =
        d.uptime;

    let html = "";

    d.cores.forEach((usage, index) => {

        const cls = getColorClass(usage);

        html += `
            <div class="core ${cls}">
                CPU${index}: ${usage}%
            </div>
        `;
    });

    document.getElementById("cores").innerHTML = html;

    let immichHtml = "";

    if (d.immich.healthy) {

        immichHtml +=
            '<div class="status-good">● HEALTHY</div><br>';

    } else {

        immichHtml +=
            '<div class="status-bad">● DEGRADED</div><br>';
    }

    for (const [name, status] of Object.entries(
        d.immich.containers
    )) {

        const cls =
            status === "Healthy"
            ? "status-good"
            : "status-bad";

        immichHtml +=
            `<div class="${cls}">${name}: ${status}</div>`;
    }

    document.getElementById("immich").innerHTML =
        immichHtml;

    document.getElementById("main_camera").innerHTML =
        cameraHtml(d.cameras.main);

    document.getElementById("mini_camera").innerHTML =
        cameraHtml(d.cameras.mini);
}

updateStats();

setInterval(updateStats, 2000);

</script>

</body>
</html>
"""


def run(cmd):
    try:
        return subprocess.check_output(
            cmd,
            shell=True,
            text=True,
            stderr=subprocess.DEVNULL
        )
    except Exception:
        return ""


def read_cpu_times():
    with open("/proc/stat", "r") as f:
        fields = list(map(int, f.readline().split()[1:]))

    idle = fields[3] + fields[4]
    total = sum(fields)

    return idle, total


def get_cpu_usage():
    global _last_idle
    global _last_total
    global _last_cpu

    idle, total = read_cpu_times()

    if _last_idle is None:
        _last_idle = idle
        _last_total = total
        return 0.0

    idle_delta = idle - _last_idle
    total_delta = total - _last_total

    _last_idle = idle
    _last_total = total

    if total_delta <= 0:
        return _last_cpu

    _last_cpu = round(
        100.0 * (1.0 - idle_delta / total_delta),
        2
    )

    return _last_cpu


def get_cpu_cores():
    global _core_prev

    cores = []

    with open("/proc/stat") as f:
        lines = f.readlines()

    for line in lines:

        if not line.startswith("cpu"):
            break

        if line.startswith("cpu "):
            continue

        parts = line.split()

        core_name = parts[0]
        vals = list(map(int, parts[1:]))

        idle = vals[3] + vals[4]
        total = sum(vals)

        if core_name not in _core_prev:
            _core_prev[core_name] = (idle, total)
            cores.append(0.0)
            continue

        prev_idle, prev_total = _core_prev[core_name]

        idle_delta = idle - prev_idle
        total_delta = total - prev_total

        _core_prev[core_name] = (idle, total)

        if total_delta <= 0:
            cores.append(0.0)
            continue

        usage = round(
            100.0 * (1.0 - idle_delta / total_delta),
            2
        )

        cores.append(usage)

    return cores


def get_temp():

    for i in range(10):

        zone = f"/sys/class/thermal/thermal_zone{i}"

        if not os.path.exists(zone):
            continue

        try:

            with open(f"{zone}/type") as f:
                if f.read().strip() != "x86_pkg_temp":
                    continue

            with open(f"{zone}/temp") as f:
                return int(f.read().strip()) / 1000

        except Exception:
            continue

    return 0


def get_gpu_temp():

    for name in os.listdir("/sys/class/hwmon"):

        hwmon = f"/sys/class/hwmon/{name}"

        try:

            with open(f"{hwmon}/name") as f:
                if f.read().strip() != "radeon":
                    continue

            with open(f"{hwmon}/temp1_input") as f:
                return round(
                    int(f.read().strip()) / 1000,
                    1
                )

        except Exception:
            continue

    return 0


def get_ram():

    total = None
    available = None

    with open("/proc/meminfo") as f:

        for line in f:

            if line.startswith("MemTotal:"):
                total = int(line.split()[1])

            elif line.startswith("MemAvailable:"):
                available = int(line.split()[1])

            if total is not None and available is not None:
                break

    if total is None or available is None:
        return {
            "used_gb": 0,
            "free_gb": 0,
            "total_gb": 0,
            "percent": 0
        }

    used = total - available

    return {
        "used_gb": round(used / 1024 / 1024, 1),
        "free_gb": round(available / 1024 / 1024, 1),
        "total_gb": round(total / 1024 / 1024, 1),
        "percent": round((used / total) * 100)
    }


def get_storage():

    mounts = {
        "/": "boot_ssd",
        "/mnt/immich": "multimedia_ssd",
        "/mnt/camera": "camera_hdd",
        "/mnt/data": "data_hdd"
    }

    result = {}

    for mount, key in mounts.items():

        try:

            st = os.statvfs(mount)

            total = st.f_blocks * st.f_frsize

            free = st.f_bfree * st.f_frsize
            avail = st.f_bavail * st.f_frsize

            used = total - free

            percent = round(
                (used / (used + avail)) * 100
            )

            result[key] = {
                "used_gb": round(used / 1024**3, 1),
                "free_gb": round(avail / 1024**3, 1),
                "percent": percent
            }

        except Exception:

            result[key] = {
                "used_gb": 0,
                "free_gb": 0,
                "percent": 0
            }

    return result


def get_disk_map():

    mounts = {
        "/": "boot_ssd",
        "/mnt/immich": "multimedia_ssd",
        "/mnt/camera": "camera_hdd",
        "/mnt/data": "data_hdd"
    }

    result = {}

    with open("/proc/mounts") as f:

        for line in f:

            parts = line.split()

            if len(parts) < 2:
                continue

            device = parts[0]
            mount = parts[1]

            if mount not in mounts:
                continue

            part = os.path.basename(device)

            try:

                real = os.path.realpath(
                    f"/sys/class/block/{part}"
                )

                disk = os.path.basename(
                    os.path.dirname(real)
                )

            except Exception:

                disk = part

            result[mounts[mount]] = disk

    return result


def get_disk_activity():

    global _disk_prev
    global _disk_map

    if _disk_map is None:
        _disk_map = get_disk_map()

    result = {}

    now = time.time()

    with open("/proc/diskstats") as f:

        for line in f:

            p = line.split()

            if len(p) < 14:
                continue

            dev = p[2]

            for name, disk in _disk_map.items():

                if dev != disk:
                    continue

                sectors_read = int(p[5])
                sectors_written = int(p[9])

                if disk not in _disk_prev:

                    _disk_prev[disk] = (
                        sectors_read,
                        sectors_written,
                        now
                    )

                    result[name] = {
                        "read_mbps": 0,
                        "write_mbps": 0
                    }

                    continue

                old_r, old_w, old_t = _disk_prev[disk]

                dt = now - old_t

                if dt <= 0:
                    dt = 1

                read_bytes = (
                    sectors_read - old_r
                ) * 512

                write_bytes = (
                    sectors_written - old_w
                ) * 512

                result[name] = {
                    "read_mbps": round(
                        read_bytes /
                        dt /
                        1024 /
                        1024,
                        2
                    ),
                    "write_mbps": round(
                        write_bytes /
                        dt /
                        1024 /
                        1024,
                        2
                    )
                }

                _disk_prev[disk] = (
                    sectors_read,
                    sectors_written,
                    now
                )

    return result


def get_interface_usage(iface):

    global _last_rx
    global _last_tx
    global _last_net_time

    global _last_ts_rx
    global _last_ts_tx
    global _last_ts_time

    try:

        with open(
            f"/sys/class/net/{iface}/statistics/rx_bytes"
        ) as f:
            rx = int(f.read().strip())

        with open(
            f"/sys/class/net/{iface}/statistics/tx_bytes"
        ) as f:
            tx = int(f.read().strip())

    except Exception:

        return {
            "rx_bps": 0,
            "tx_bps": 0
        }

    now = time.time()

    if iface == "tailscale0":

        if _last_ts_rx is None:

            _last_ts_rx = rx
            _last_ts_tx = tx
            _last_ts_time = now

            return {
                "rx_bps": 0,
                "tx_bps": 0
            }

        dt = now - _last_ts_time

        rx_bps = ((rx - _last_ts_rx) * 8) / dt
        tx_bps = ((tx - _last_ts_tx) * 8) / dt

        _last_ts_rx = rx
        _last_ts_tx = tx
        _last_ts_time = now

    else:

        if _last_rx is None:

            _last_rx = rx
            _last_tx = tx
            _last_net_time = now

            return {
                "rx_bps": 0,
                "tx_bps": 0
            }

        dt = now - _last_net_time

        rx_bps = ((rx - _last_rx) * 8) / dt
        tx_bps = ((tx - _last_tx) * 8) / dt

        _last_rx = rx
        _last_tx = tx
        _last_net_time = now

    return {
        "rx_bps": round(rx_bps),
        "tx_bps": round(tx_bps)
    }


def get_immich_status():

    cmd = (
        f"cd {IMMICH_COMPOSE_DIR} && "
        "docker compose ps --format json"
    )

    out = run(cmd)

    if not out.strip():

        return {
            "healthy": False,
            "containers": {}
        }

    containers = {}
    all_healthy = True

    for line in out.splitlines():

        try:

            c = json.loads(line)

            name = c.get("Name", "Unknown")
            state = c.get("State", "Unknown")
            health = c.get("Health", "")

            if state != "running":

                status = state.title()
                all_healthy = False

            elif health and health != "healthy":

                status = health.title()
                all_healthy = False

            else:

                status = "Healthy"

            containers[name] = status

        except Exception:
            pass

    return {
        "healthy": all_healthy,
        "containers": containers
    }


def ping_camera(ip):

    rc = subprocess.call(
        [
            "ping",
            "-c", "1",
            "-W", "1",
            ip
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    return rc == 0


def latest_file_age(camera):

    newest = 0

    for root, dirs, files in os.walk(
        CAMERA_RECORDINGS[camera]
    ):

        for f in files:

            if not f.lower().endswith((".mp4", ".mkv")):
                continue

            path = os.path.join(root, f)

            try:

                size = os.path.getsize(path)

                if size < 1024:
                    continue

                mtime = os.path.getmtime(path)

                if mtime > newest:
                    newest = mtime

            except Exception:
                pass

    if newest == 0:
        return None

    return int(time.time() - newest)


def latest_recorded_file(camera):

    files = []

    try:

        for root, dirs, filenames in os.walk(
            CAMERA_RECORDINGS[camera]
        ):

            for f in filenames:

                if not f.endswith(".mp4"):
                    continue

                path = os.path.join(root, f)

                try:

                    files.append(
                        (
                            os.path.getmtime(path),
                            f
                        )
                    )

                except Exception:
                    pass

    except Exception:
        return None

    if not files:
        return None

    files.sort(reverse=True)

    # newest file is probably still being written

    if len(files) >= 2:
        return files[1][1]

    return files[0][1]


def get_camera_status():

    cameras = {}

    for name, ip in {
        "main": MAIN_CAMERA_IP,
        "mini": MINI_CAMERA_IP
    }.items():

        age = latest_file_age(name)

        cameras[name] = {
            "live": ping_camera(ip),
            "recording": (
                age is not None and
                age < RECORDING_AGE_LIMIT
            ),
            "last_file": latest_recorded_file(name)
        }

    return cameras


def get_uptime():

    return run("uptime -p").strip()


@app.route("/")
def index():

    return render_template_string(HTML)


@app.route("/api/stats")
def stats():

    return jsonify({
        "cpu": get_cpu_usage(),
        "cores": get_cpu_cores(),
        "temp": get_temp(),
        "gpu_temp": get_gpu_temp(),
        "ram": get_ram(),
        "storage": get_storage(),
        "disk_activity": get_disk_activity(),
        "network": get_interface_usage("enp0s25"),
        "tailscale": get_interface_usage("tailscale0"),
        "immich": get_immich_status(),
        "cameras": get_camera_status(),
        "uptime": get_uptime()
    })


idle, total = read_cpu_times()
_last_idle = idle
_last_total = total

get_cpu_cores()

if __name__ == "__main__":

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )