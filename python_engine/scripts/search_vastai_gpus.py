import json
from pathlib import Path
import requests

env_path = Path("/root/projects/ai_image_studio/cloud_backend/.env")
env_vars = {}
with open(env_path) as f:
    for line in f:
        if line.strip() and not line.startswith("#") and "=" in line:
            k, v = line.strip().split("=", 1)
            env_vars[k.strip()] = v.strip().strip("\"'")

api_key = env_vars.get("VASTAI_API_KEY")
headers = {"Authorization": f"Bearer {api_key}"}

q = {
    "verified": {"eq": True},
    "rentable": {"eq": True},
    "num_gpus": {"eq": 1},
    "gpu_ram": {"gte": 16000},
    "disk_space": {"gte": 50},
    "inet_down": {"gte": 250},
    "inet_down_cost": {"lte": 0.005},
    "order": [["dph_total", "asc"]],
}

r = requests.get(
    "https://console.vast.ai/api/v0/bundles",
    params={"q": json.dumps(q)},
    headers=headers,
    timeout=15,
)
offers = r.json().get("offers", [])
print(f"Total suitable offers found: {len(offers)}")
for o in offers[:12]:
    gpu = o.get("gpu_name")
    vram = round(o.get("gpu_ram", 0) / 1024, 1)
    dph = round(o.get("dph_total", 0), 3)
    down = round(o.get("inet_down", 0))
    geo = o.get("geolocation", "Unknown")
    print(f"Offer ID: {o['id']} | {gpu} ({vram} GB) | ${dph}/hr | {geo} | {down} Mbps")
