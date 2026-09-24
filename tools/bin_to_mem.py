#!/usr/bin/env python3

import argparse
from pathlib import Path


def write_mem_image(data: bytes, output_path: Path, word_bytes: int) -> None:
    padding = (-len(data)) % word_bytes
    padded_data = data + bytes(padding)

    with output_path.open("w", encoding="ascii") as output_file:
        for offset in range(0, len(padded_data), word_bytes):
            chunk = padded_data[offset:offset + word_bytes]
            word = int.from_bytes(chunk, byteorder="little")
            output_file.write(f"{word:0{word_bytes * 2}x}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Convert a flat little-endian binary image into the "
            "32-bit IMEM and 64-bit DMEM hex formats used by the RTL testbench."
        )
    )

    parser.add_argument(
        "input",
        type=Path,
        help="Flat binary input image.",
    )

    parser.add_argument(
        "--imem",
        type=Path,
        required=True,
        help="Output file containing 32-bit IMEM words.",
    )

    parser.add_argument(
        "--dmem",
        type=Path,
        required=True,
        help="Output file containing 64-bit DMEM words.",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not args.input.is_file():
        raise SystemExit(f"ERROR: input file does not exist: {args.input}")

    data = args.input.read_bytes()

    if not data:
        raise SystemExit(f"ERROR: input file is empty: {args.input}")

    args.imem.parent.mkdir(parents=True, exist_ok=True)
    args.dmem.parent.mkdir(parents=True, exist_ok=True)

    write_mem_image(data, args.imem, word_bytes=4)
    write_mem_image(data, args.dmem, word_bytes=8)

    print(f"Input bytes : {len(data)}")
    print(f"IMEM words  : {(len(data) + 3) // 4}")
    print(f"DMEM words  : {(len(data) + 7) // 8}")
    print(f"IMEM output : {args.imem}")
    print(f"DMEM output : {args.dmem}")


if __name__ == "__main__":
    main()
