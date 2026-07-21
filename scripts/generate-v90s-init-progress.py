#!/usr/bin/env python3
import argparse
import pathlib
import struct


WIDTH = 640
HEIGHT = 480
VIRTUAL_HEIGHT = 960

FONT = {
    " ": ["00000"] * 7,
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
}


def color(value):
    return struct.pack("<I", value)


def fill_rect(frame, x, y, width, height, value):
    pixel = color(value)
    row = pixel * max(0, width)
    for py in range(max(0, y), min(HEIGHT, y + height)):
        start = (py * WIDTH + max(0, x)) * 4
        frame[start : start + len(row)] = row


def draw_text(frame, text, y, scale, value):
    text = text.upper()
    glyph_width = 6 * scale
    width = max(0, len(text) * glyph_width - scale)
    x = (WIDTH - width) // 2
    for char in text:
        glyph = FONT.get(char, FONT[" "])
        for row_index, row in enumerate(glyph):
            for column, enabled in enumerate(row):
                if enabled == "1":
                    fill_rect(
                        frame,
                        x + column * scale,
                        y + row_index * scale,
                        scale,
                        scale,
                        value,
                    )
        x += glyph_width


def render(message, percent, error=False):
    background = 0xFF071014
    panel = 0xFF152329
    text = 0xFFE8F1F2
    muted = 0xFF8FA6AA
    accent = 0xFFE34A4A if error else 0xFFFF8A00
    frame = bytearray(color(background) * (WIDTH * HEIGHT))

    fill_rect(frame, 0, 0, WIDTH, 8, accent)
    draw_text(frame, "PLUMOS V90S", 68, 5, text)
    fill_rect(frame, 56, 150, WIDTH - 112, 180, panel)
    draw_text(frame, message, 205, 4, text)
    draw_text(frame, "DO NOT POWER OFF" if not error else "CHECK PLUMOS LOGS", 270, 3, muted)

    bar_x, bar_y, bar_w, bar_h = 80, 370, 480, 28
    fill_rect(frame, bar_x, bar_y, bar_w, bar_h, 0xFF293B40)
    fill_rect(frame, bar_x + 4, bar_y + 4, int((bar_w - 8) * percent / 100), bar_h - 8, accent)
    draw_text(frame, f"{percent}", 420, 3, text)

    page = bytes(frame)
    return page + page


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    output_dir = pathlib.Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    stages = {
        "boot": ("BOOTING PLUMOS", 5, False),
        "prepare": ("PREPARING STORAGE", 10, False),
        "resize": ("RESIZING SYSTEM", 30, False),
        "userdata": ("CREATING USER STORAGE", 50, False),
        "verify": ("VERIFYING SYSTEM", 70, False),
        "mount": ("MOUNTING SYSTEM", 85, False),
        "start": ("STARTING PLUMOS", 95, False),
        "update_verify": ("VERIFYING UPDATE", 15, False),
        "update_runtime": ("UPDATING RUNTIME", 45, False),
        "update_system": ("UPDATING SYSTEM", 55, False),
        "update_finalize": ("FINALIZING UPDATE", 90, False),
        "update_rollback": ("RESTORING PREVIOUS", 70, False),
        "update_error": ("UPDATE FAILED", 100, True),
        "error": ("STARTUP FAILED", 100, True),
    }
    expected_size = WIDTH * VIRTUAL_HEIGHT * 4
    for name, (message, percent, error) in stages.items():
        payload = render(message, percent, error)
        if len(payload) != expected_size:
            raise RuntimeError(f"unexpected frame size for {name}: {len(payload)}")
        (output_dir / f"{name}.raw").write_bytes(payload)


if __name__ == "__main__":
    main()
