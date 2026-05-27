#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""
models_benchmark.py - Benchmark all models on an OpenAI-compatible llama.cpp server.

Usage:
    ./models_benchmark.py http://localhost:8081
    ./models_benchmark.py http://localhost:8081 --output results.csv
"""

import argparse
import csv
import curses
import json
import sys
import threading
import time
import urllib.request
from datetime import datetime

WARMUP_PROMPT = "Say 'ready' and nothing else."
BENCHMARK_PROMPT = "Briefly describe the best web framework."
REQUEST_TIMEOUT = 600  # seconds per request

# Statuses
ST_PENDING = "pending"
ST_WARMUP = "warming up"
ST_PROMPTING = "prompting"
ST_DONE = "done"
ST_ERROR = "error"

# Shared state
_state: list[dict] = []
_lock = threading.Lock()
_done = threading.Event()

SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

STATUS_SYMBOL = {
    ST_PENDING: "○",
    ST_DONE: "✓",
    ST_ERROR: "✗",
}

# curses color pair indices
C_DEFAULT = 1
C_GREEN = 2
C_YELLOW = 3
C_CYAN = 4
C_RED = 5
C_WHITE = 6

STATUS_COLOR = {
    ST_PENDING: C_DEFAULT,
    ST_WARMUP: C_YELLOW,
    ST_PROMPTING: C_CYAN,
    ST_DONE: C_GREEN,
    ST_ERROR: C_RED,
}


# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------


def api_request(base_url: str, path: str, payload: dict | None = None) -> dict:
    url = base_url.rstrip("/") + path
    if payload is None:
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
    else:
        data = json.dumps(payload).encode()
        request = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            method="POST",
        )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as http_response:
        return json.loads(http_response.read().decode())


def chat(base_url: str, model: str, prompt: str, max_tokens: int = 512) -> dict:
    return api_request(
        base_url,
        "/v1/chat/completions",
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "stream": False,
        },
    )


# ---------------------------------------------------------------------------
# Worker thread
# ---------------------------------------------------------------------------


def _set(idx: int, **kwargs) -> None:
    with _lock:
        _state[idx].update(kwargs)


def run_benchmarks(base_url: str, models: list[str]) -> None:
    for model_idx, model_id in enumerate(models):
        # Brief pause to let the server unload the previous model
        if model_idx > 0:
            time.sleep(1)

        # Warm-up
        _set(model_idx, status=ST_WARMUP)
        try:
            warmup_start = time.monotonic()
            chat(base_url, model_id, WARMUP_PROMPT, max_tokens=64)
            _set(model_idx, warmup_elapsed_s=round(time.monotonic() - warmup_start, 2))
        except Exception as exc:
            _set(model_idx, status=ST_ERROR, error=str(exc))
            continue

        # Benchmark
        _set(model_idx, status=ST_PROMPTING)
        try:
            bench_start = time.monotonic()
            api_response = chat(base_url, model_id, BENCHMARK_PROMPT)
            client_elapsed = time.monotonic() - bench_start

            # Prefer llama.cpp server-side timings over client-side estimates
            timings = api_response.get("timings", {})
            usage = api_response.get("usage", {})

            if timings.get("predicted_n"):
                completion_tokens = int(timings["predicted_n"])
                tokens_per_sec = round(timings.get("predicted_per_second", 0), 2)
                elapsed = round(timings["predicted_ms"] / 1000, 2)
            else:
                completion_tokens = usage.get("completion_tokens", 0)
                elapsed = round(client_elapsed, 2)
                tokens_per_sec = (
                    round(completion_tokens / elapsed, 2) if elapsed > 0 else 0
                )

            choices = api_response.get("choices", [])
            response_text = (
                choices[0].get("message", {}).get("content", "").strip()
                if choices
                else ""
            )
            _set(
                model_idx,
                status=ST_DONE,
                elapsed_s=elapsed,
                prompt_tokens=usage.get("prompt_tokens"),
                completion_tokens=completion_tokens,
                total_tokens=usage.get("total_tokens"),
                tokens_per_second=tokens_per_sec,
                response=response_text,
            )
        except Exception as exc:
            _set(model_idx, status=ST_ERROR, error=str(exc))

    _done.set()


# ---------------------------------------------------------------------------
# TUI
# ---------------------------------------------------------------------------


def _safe_addstr(
    win: "curses._CursesWindow", row: int, col: int, text: str, attr: int = 0
) -> None:
    """addstr that silently ignores out-of-bounds writes."""
    height, width = win.getmaxyx()
    if row >= height or col >= width:
        return
    try:
        win.addstr(row, col, text[: width - col - 1], attr)
    except curses.error:
        pass


def draw(stdscr: "curses._CursesWindow", output_file: str) -> None:
    curses.curs_set(0)
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(C_DEFAULT, -1, -1)
    curses.init_pair(C_GREEN, curses.COLOR_GREEN, -1)
    curses.init_pair(C_YELLOW, curses.COLOR_YELLOW, -1)
    curses.init_pair(C_CYAN, curses.COLOR_CYAN, -1)
    curses.init_pair(C_RED, curses.COLOR_RED, -1)
    curses.init_pair(C_WHITE, curses.COLOR_WHITE, -1)

    # Column offsets
    COL_MODEL = 0
    COL_STATUS = 36
    COL_WARMUP = 54
    COL_TPS = 64
    COL_TOKENS = 74
    COL_ELAPSED = 84

    frame = 0
    while True:
        stdscr.erase()
        height, width = stdscr.getmaxyx()
        row = 0

        # Title
        title = " ◈  Model Benchmark "
        _safe_addstr(
            stdscr,
            row,
            max(0, (width - len(title)) // 2),
            title,
            curses.A_BOLD | curses.color_pair(C_WHITE),
        )
        row += 1
        _safe_addstr(stdscr, row, 0, "─" * (width - 1))
        row += 1

        # Column headers
        header_attr = curses.A_BOLD | curses.color_pair(C_WHITE)
        _safe_addstr(stdscr, row, COL_MODEL, f"{'Model':<35}", header_attr)
        _safe_addstr(stdscr, row, COL_STATUS, f"{'Status':<17}", header_attr)
        _safe_addstr(stdscr, row, COL_WARMUP, f"{'Warmup':>9}", header_attr)
        _safe_addstr(stdscr, row, COL_TPS, f"{'t/s':>9}", header_attr)
        _safe_addstr(stdscr, row, COL_TOKENS, f"{'tokens':>9}", header_attr)
        _safe_addstr(stdscr, row, COL_ELAPSED, f"{'elapsed':>9}", header_attr)
        row += 1
        _safe_addstr(stdscr, row, 0, "─" * (width - 1))
        row += 1

        with _lock:
            snapshot = [dict(s) for s in _state]

        done_count = 0
        for entry in snapshot:
            if row >= height - 2:
                break
            status = entry["status"]
            color = curses.color_pair(STATUS_COLOR.get(status, C_DEFAULT))

            if status in (ST_WARMUP, ST_PROMPTING):
                status_icon = SPINNER[frame % len(SPINNER)]
            else:
                status_icon = STATUS_SYMBOL.get(status, "?")

            if status in (ST_DONE, ST_ERROR):
                done_count += 1

            warmup = (
                f"{entry['warmup_elapsed_s']}s"
                if entry["warmup_elapsed_s"] is not None
                else "-"
            )
            tps = (
                str(entry["tokens_per_second"])
                if entry["tokens_per_second"] is not None
                else "-"
            )
            tokens = (
                str(entry["completion_tokens"])
                if entry["completion_tokens"] is not None
                else "-"
            )
            elapsed = (
                f"{entry['elapsed_s']}s" if entry["elapsed_s"] is not None else "-"
            )

            _safe_addstr(stdscr, row, COL_MODEL, f"{entry['model'][:34]:<35}")
            _safe_addstr(stdscr, row, COL_STATUS, f"{status_icon} {status:<15}", color)
            _safe_addstr(stdscr, row, COL_WARMUP, f"{warmup:>9}")
            _safe_addstr(
                stdscr,
                row,
                COL_TPS,
                f"{tps:>9}",
                color if status == ST_DONE else curses.color_pair(C_DEFAULT),
            )
            _safe_addstr(stdscr, row, COL_TOKENS, f"{tokens:>9}")
            _safe_addstr(stdscr, row, COL_ELAPSED, f"{elapsed:>9}")
            row += 1

        # Footer
        _safe_addstr(stdscr, height - 2, 0, "─" * (width - 1))
        total = len(snapshot)
        if _done.is_set():
            footer = f" Done! {done_count}/{total} complete  •  {output_file}  •  press any key to exit"
        else:
            footer = f" Running… {done_count}/{total} complete"
        _safe_addstr(stdscr, height - 1, 0, footer)

        stdscr.refresh()
        frame += 1

        if _done.is_set():
            stdscr.nodelay(False)
            stdscr.getch()
            break
        else:
            stdscr.nodelay(True)
            stdscr.getch()
            time.sleep(0.1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Benchmark all models on a llama.cpp server."
    )
    parser.add_argument(
        "url", help="Base URL of the OpenAI-compatible API (e.g. http://localhost:8081)"
    )
    parser.add_argument(
        "--output",
        default=f"benchmark_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv",
        help="Output CSV file (default: benchmark_<timestamp>.csv)",
    )
    args = parser.parse_args()
    base_url = args.url.rstrip("/")

    # Discover models before starting the TUI
    try:
        models_resp = api_request(base_url, "/v1/models")
    except Exception as exc:
        print(f"ERROR: could not reach API: {exc}", file=sys.stderr)
        sys.exit(1)

    models = [m["id"] for m in models_resp.get("data", [])]
    if not models:
        print("No models returned by the API.", file=sys.stderr)
        sys.exit(1)

    for model_id in models:
        _state.append(
            {
                "host": base_url,
                "model": model_id,
                "status": ST_PENDING,
                "warmup_elapsed_s": None,
                "elapsed_s": None,
                "prompt_tokens": None,
                "completion_tokens": None,
                "total_tokens": None,
                "tokens_per_second": None,
                "response": None,
                "error": None,
            }
        )

    worker = threading.Thread(
        target=run_benchmarks, args=(base_url, models), daemon=True
    )
    worker.start()

    curses.wrapper(draw, args.output)

    worker.join()

    # Write CSV
    fieldnames = [
        "host",
        "model",
        "tokens_per_second",
        "warmup_elapsed_s",
        "elapsed_s",
        "prompt_tokens",
        "completion_tokens",
        "total_tokens",
        "response",
        "error",
    ]
    with open(args.output, "w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        with _lock:
            sorted_state = sorted(
                _state,
                key=lambda row: row["tokens_per_second"] or 0,
                reverse=True,
            )
        writer.writerows(sorted_state)

    print(f"Results written to {args.output}")


if __name__ == "__main__":
    main()
