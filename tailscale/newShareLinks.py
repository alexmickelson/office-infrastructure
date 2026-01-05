#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3Packages.requests python3Packages.python-dotenv

import os
import requests
from dotenv import load_dotenv

# Load .env variables
load_dotenv()

API_KEY = os.getenv("API_KEY")
TAILNET = os.getenv("TAILNET")

# Array of machines to create share links for
MACHINES = [
    "alex-office1",
    "alex-office2",
    "alex-office3",
    "alex-office4",
    "alex-office5",
]


def get_all_devices():
    """Fetch all devices from the Tailscale API."""
    response = requests.get(
        f"https://api.tailscale.com/api/v2/tailnet/{TAILNET}/devices",
        headers={"Authorization": f"Bearer {API_KEY}"},
    )
    response.raise_for_status()
    devices = response.json()["devices"]
    return devices


def get_device_invites(device_id):
    """Get all device invites for a specific device."""
    response = requests.get(
        f"https://api.tailscale.com/api/v2/device/{device_id}/device-invites",
        headers={"Authorization": f"Bearer {API_KEY}"},
    )
    response.raise_for_status()
    return response.json()


def delete_reusable_invites(device_id, invites):
    """Delete all reusable (multi-use) invites that haven't been accepted."""
    deleted_count = 0
    for invite in invites:
        # Delete if it's multiUse and not accepted
        if invite.get("multiUse", False) and not invite.get("accepted", False):
            invite_id = invite["id"]
            print(f"  Deleting reusable invite {invite_id}...")
            delete_response = requests.delete(
                f"https://api.tailscale.com/api/v2/device-invites/{invite_id}",
                headers={"Authorization": f"Bearer {API_KEY}"},
            )
            delete_response.raise_for_status()
            deleted_count += 1
    return deleted_count


def create_share_link(device_id):
    """Create a new reusable share link for a device."""
    response = requests.post(
        f"https://api.tailscale.com/api/v2/device/{device_id}/device-invites",
        headers={"Authorization": f"Bearer {API_KEY}"},
        json=[{"multiUse": True}],
    )

    if not response.ok:
        print(f"  Error creating share link: {response.status_code}")
        print(f"  Response: {response.text}")
        return ""

    result = response.json()
    # API returns array, get first item
    if isinstance(result, list) and len(result) > 0:
        return result[0].get("inviteUrl", "")
    return ""


def main():
    print("Fetching all devices...")
    all_devices = get_all_devices()

    # Create a map of device names to device info
    device_map = {}
    for device in all_devices:
        name = device.get("name", "").split(".")[0]  # Get hostname without domain
        if name in MACHINES:
            device_map[name] = {
                "id": device["id"],
                "name": name,
                "addresses": device.get("addresses", []),
            }

    # Check if we found all machines
    missing = set(MACHINES) - set(device_map.keys())
    if missing:
        print(f"Warning: Could not find devices: {', '.join(missing)}")

    print("\nRemoving all pending reusable share links...")
    total_deleted = 0
    for machine_name in sorted(device_map.keys()):
        device_info = device_map[machine_name]
        device_id = device_info["id"]
        print(f"\nChecking {machine_name}...")

        invites = get_device_invites(device_id)
        if isinstance(invites, list):
            deleted = delete_reusable_invites(device_id, invites)
            total_deleted += deleted
            if deleted > 0:
                print(f"  Deleted {deleted} reusable invite(s)")

    print(f"\nTotal deleted: {total_deleted} reusable invites")

    print("\nCreating new share links...")
    markdown_lines = []

    for machine_name in sorted(device_map.keys()):
        device_info = device_map[machine_name]
        device_id = device_info["id"]
        addresses = device_info["addresses"]

        # Get the first IP address (usually the tailscale IP)
        ip_address = addresses[0] if addresses else "No IP"

        print(f"Creating share link for {machine_name}...")
        share_url = create_share_link(device_id)

        # Add to markdown
        markdown_lines.append(f"- {machine_name} - {ip_address} [Share Link]({share_url})")

    print("\n".join(markdown_lines))


if __name__ == "__main__":
    main()
