#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3Packages.requests python3Packages.python-dotenv

import os
import sys
import requests
from dotenv import load_dotenv
import shutil


# Load .env variables
load_dotenv()

API_KEY = os.getenv("API_KEY")
TAILNET = os.getenv("TAILNET")


def get_all_device_ids():
    """Fetch all device IDs from the Tailscale API."""
    response = requests.get(
        f"https://api.tailscale.com/api/v2/tailnet/{TAILNET}/devices",
        headers={"Authorization": f"Bearer {API_KEY}"},
    )
    response.raise_for_status()
    devices = response.json()["devices"]
    device_map = {
        device["id"]: device.get("name", str(device["id"])) for device in devices
    }
    return device_map


def collect_all_invites(device_map):
    """Collect all invites with email addresses across all devices."""
    all_invites = []

    print("Fetching device invites...")
    for device_id, device_name in device_map.items():
        invites_response = requests.get(
            f"https://api.tailscale.com/api/v2/device/{device_id}/device-invites",
            headers={"Authorization": f"Bearer {API_KEY}"},
        )
        invites_response.raise_for_status()
        invites = invites_response.json()

        if isinstance(invites, list):
            for invite in invites:
                if "acceptedBy" in invite and "loginName" in invite["acceptedBy"]:
                    invite_email = invite["acceptedBy"]["loginName"]
                    all_invites.append(
                        {
                            "email": invite_email,
                            "invite_id": invite["id"],
                            "device_id": device_id,
                            "device_name": device_name,
                        }
                    )

    return all_invites


def group_invites_by_email(all_invites):
    """Group invites by email address."""
    email_groups = {}
    for invite in all_invites:
        email = invite["email"]
        if email not in email_groups:
            email_groups[email] = []
        email_groups[email].append(invite)
    return email_groups


def get_terminal_height():
    """Get the current terminal height."""
    import shutil

    return shutil.get_terminal_size().lines


# ANSI color codes
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"

    # Foreground colors
    BLACK = "\033[30m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"

    # Background colors
    BG_BLACK = "\033[40m"
    BG_RED = "\033[41m"
    BG_GREEN = "\033[42m"
    BG_YELLOW = "\033[43m"
    BG_BLUE = "\033[44m"
    BG_MAGENTA = "\033[45m"
    BG_CYAN = "\033[46m"
    BG_WHITE = "\033[47m"


def display_menu(email_groups, selected_emails, current_index, scroll_offset):
    """Display the TUI menu with scrolling support."""
    import sys

    terminal_width = shutil.get_terminal_size().columns
    terminal_height = get_terminal_height()

    # Build output as list of lines
    lines = []

    # Header
    lines.append(f"{Colors.CYAN}{'=' * terminal_width}{Colors.RESET}")
    lines.append(
        f"{Colors.BOLD}{Colors.CYAN}Tailscale Device Invite Revocation Tool{Colors.RESET}"
    )
    lines.append(f"{Colors.CYAN}{'=' * terminal_width}{Colors.RESET}")
    lines.append("")
    lines.append(
        f"{Colors.DIM}Use {Colors.YELLOW}↑/↓{Colors.RESET}{Colors.DIM} or {Colors.YELLOW}j/k{Colors.RESET}{Colors.DIM} to navigate, {Colors.GREEN}SPACE{Colors.RESET}{Colors.DIM} to toggle, {Colors.GREEN}ENTER{Colors.RESET}{Colors.DIM} to confirm, {Colors.RED}Q{Colors.RESET}{Colors.DIM} to quit{Colors.RESET}"
    )
    lines.append("")

    header_lines = len(lines)
    footer_lines = 2  # Separator line + status line
    scroll_indicator_lines = 2  # Top and bottom indicators
    available_lines = (
        terminal_height
        - header_lines
        - footer_lines
        - scroll_indicator_lines
        - 1  # -1 to prevent overflow
    )
    max_visible_items = max(1, available_lines)

    emails = sorted(email_groups.keys())

    # Calculate visible window
    visible_start = scroll_offset
    visible_end = min(scroll_offset + max_visible_items, len(emails))

    # Show scroll indicator if needed
    if scroll_offset > 0:
        lines.append(f"  {Colors.YELLOW}▲ More items above...{Colors.RESET}")
    else:
        lines.append("")

    for i in range(visible_start, visible_end):
        email = emails[i]
        invite_count = len(email_groups[email])

        is_current = i == current_index
        is_selected = email in selected_emails

        # Styling based on state
        if is_current and is_selected:
            prefix = f"{Colors.GREEN}→ {Colors.RESET}"
            checkbox = f"{Colors.GREEN}{Colors.BOLD}[x]{Colors.RESET}"
            email_color = f"{Colors.GREEN}{Colors.BOLD}"
        elif is_current:
            prefix = f"{Colors.CYAN}→ {Colors.RESET}"
            checkbox = f"{Colors.CYAN}[ ]{Colors.RESET}"
            email_color = f"{Colors.CYAN}{Colors.BOLD}"
        elif is_selected:
            prefix = "  "
            checkbox = f"{Colors.GREEN}[x]{Colors.RESET}"
            email_color = f"{Colors.GREEN}"
        else:
            prefix = "  "
            checkbox = f"{Colors.DIM}[ ]{Colors.RESET}"
            email_color = ""

        count_color = Colors.YELLOW if invite_count > 1 else Colors.DIM

        # Build the line - show email and count only (no devices)
        lines.append(
            f"{prefix}{checkbox} {email_color}{email}{Colors.RESET} {count_color}({invite_count}){Colors.RESET}"
        )

    # Bottom scroll indicator
    if visible_end < len(emails):
        lines.append(f"  {Colors.YELLOW}▼ More items below...{Colors.RESET}")
    else:
        lines.append("")

    # Footer
    lines.append("")
    lines.append(f"{Colors.CYAN}{'=' * terminal_width}{Colors.RESET}")

    selected_count = len(selected_emails)
    total_invites = sum(len(email_groups[e]) for e in selected_emails)

    selected_text = f"{Colors.GREEN if selected_count > 0 else Colors.DIM}Selected: {selected_count} users{Colors.RESET}"
    invites_text = f"{Colors.YELLOW if total_invites > 0 else Colors.DIM}Total invites: {total_invites}{Colors.RESET}"
    range_text = f"{Colors.DIM}Showing {visible_start + 1}-{visible_end} of {len(emails)}{Colors.RESET}"

    lines.append(f"{selected_text} | {invites_text} | {range_text}")

    # Clear screen, move to top, and print all lines at once (without trailing newline to avoid cursor on new line)
    print("\033[2J\033[H", end="")
    print("\n".join(lines), end="", flush=True)


def get_key():
    """Get a single keypress from stdin."""
    import termios
    import tty

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
        if ch == "\x1b":  # Escape sequence
            ch += sys.stdin.read(2)
        return ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def delete_selected_invites(email_groups, selected_emails):
    """Delete invites for selected emails."""
    print(f"\n{Colors.CYAN}{'=' * 80}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.RED}Deleting invites...{Colors.RESET}")
    print(f"{Colors.CYAN}{'=' * 80}{Colors.RESET}")

    for email in selected_emails:
        invites = email_groups[email]
        print(
            f"\n{Colors.YELLOW}Deleting invites for {Colors.BOLD}{email}{Colors.RESET}:"
        )
        for invite_data in invites:
            invite_id = invite_data["invite_id"]
            device_name = invite_data["device_name"]
            print(
                f"  {Colors.DIM}Deleting from {Colors.BLUE}{device_name}{Colors.RESET}..."
            )
            delete_response = requests.delete(
                f"https://api.tailscale.com/api/v2/device-invites/{invite_id}",
                headers={"Authorization": f"Bearer {API_KEY}"},
            )
            delete_response.raise_for_status()
            print(f"  {Colors.GREEN}✓ Deleted invite {invite_id}{Colors.RESET}")

    print(f"\n{Colors.CYAN}{'=' * 80}{Colors.RESET}")
    print(
        f"{Colors.GREEN}{Colors.BOLD}Done! Deleted invites for {len(selected_emails)} users.{Colors.RESET}"
    )


def main():
    print("Fetching all devices...")
    device_map = get_all_device_ids()

    if not device_map:
        print("No devices found.")
        return

    all_invites = collect_all_invites(device_map)

    if not all_invites:
        print("No invites with email addresses found.")
        return

    email_groups = group_invites_by_email(all_invites)
    emails = sorted(email_groups.keys())

    selected_emails = set()
    current_index = 0
    scroll_offset = 0

    while True:
        # Auto-scroll to keep current item visible
        terminal_height = get_terminal_height()
        # Match the calculation in display_menu: header(6) + top_scroll(1) + bottom_scroll(1) + footer(2) + buffer(1) = 11
        max_visible_items = max(1, terminal_height - 11)

        if current_index < scroll_offset:
            scroll_offset = current_index
        elif current_index >= scroll_offset + max_visible_items:
            scroll_offset = current_index - max_visible_items + 1

        display_menu(email_groups, selected_emails, current_index, scroll_offset)

        key = get_key()

        if key == "\x1b[A" or key == "k":  # Up arrow or k
            current_index = (current_index - 1) % len(emails)
        elif key == "\x1b[B" or key == "j":  # Down arrow or j
            current_index = (current_index + 1) % len(emails)
        elif key == " ":  # Space
            current_email = emails[current_index]
            if current_email in selected_emails:
                selected_emails.remove(current_email)
            else:
                selected_emails.add(current_email)
        elif key == "\r" or key == "\n":  # Enter
            if selected_emails:
                print("\033[2J\033[H")  # Clear screen
                delete_selected_invites(email_groups, selected_emails)

                # Refresh the data and return to menu
                print(f"\n{Colors.CYAN}Refreshing data...{Colors.RESET}")
                all_invites = collect_all_invites(device_map)
                if not all_invites:
                    print(f"{Colors.GREEN}No more invites found!{Colors.RESET}")
                    input("Press Enter to exit...")
                    break

                email_groups = group_invites_by_email(all_invites)
                emails = sorted(email_groups.keys())
                selected_emails = set()
                current_index = 0
                scroll_offset = 0

                print(f"{Colors.GREEN}Press any key to continue...{Colors.RESET}")
                get_key()
            else:
                print("\nNo users selected. Exiting.")
                break
        elif key == "q" or key == "\x03":  # q or Ctrl+C
            print("\nCancelled.")
            break


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nCancelled.")
        sys.exit(0)
