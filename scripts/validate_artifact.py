"""Read-only integrity and schema checks for the BFMScan artifact."""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from parse_bfm import parse_tshark_line  # noqa: E402


def load_folder(folder: Path) -> tuple[np.ndarray, np.ndarray, list[str]]:
    timestamps: list[float] = []
    matrices: list[np.ndarray] = []
    macs: list[str] = []
    for path in sorted(folder.glob("packets_*.mat")):
        loaded = loadmat(path, squeeze_me=False)
        required = {"packet_timestamps", "packet_infos", "ether_srcs"}
        missing = required - set(loaded)
        if missing:
            raise AssertionError(f"{path} is missing variables: {sorted(missing)}")
        chunk_time = np.asarray(loaded["packet_timestamps"]).reshape(-1)
        chunk_info = np.asarray(loaded["packet_infos"])
        chunk_macs = np.asarray(loaded["ether_srcs"]).reshape(-1)
        if chunk_info.shape[0] != chunk_time.size:
            raise AssertionError(f"{path}: packet/timestamp count mismatch")
        timestamps.extend(float(value) for value in chunk_time)
        matrices.extend(chunk_info[index] for index in range(chunk_info.shape[0]))
        macs.extend(str(value).strip() for value in chunk_macs)
    if not timestamps:
        raise AssertionError(f"no MAT packets found in {folder}")
    order = np.argsort(timestamps)
    return (
        np.asarray(timestamps)[order],
        np.stack(matrices, axis=0)[order],
        [macs[index] for index in order],
    )


def raw_summary(path: Path) -> dict[str, object]:
    input_lines = 0
    parsed = []
    skipped = 0
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            input_lines += 1
            try:
                parsed.append(parse_tshark_line(line))
            except ValueError:
                skipped += 1
    return {
        "input_lines": input_lines,
        "parsed_packets": len(parsed),
        "skipped_lines": skipped,
        "packets": parsed,
    }


def main() -> int:
    required_paths = [
        ROOT / "README.md",
        ROOT / "reproduce_figures.py",
        ROOT / "paper" / "figure_data.npz",
        ROOT / "parse_bfm.py",
        ROOT / "run_all.m",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required_paths if not path.exists()]
    if missing:
        raise AssertionError(f"required artifact files are missing: {missing}")

    cases = [
        (
            "tracking",
            ROOT
            / "experiment"
            / "wireshark_data"
            / "8_27"
            / "ap8_27_move.txt",
            ROOT / "experiment" / "v_data" / "ap8_27_move",
            323,
        ),
        (
            "respiration",
            ROOT / "experiment" / "wireshark_data" / "8_7" / "bm8_7_br.txt",
            ROOT / "experiment" / "v_data" / "BFM_data8_7_br",
            192,
        ),
    ]

    for name, raw_path, mat_folder, expected_count in cases:
        raw = raw_summary(raw_path)
        timestamps, matrices, macs = load_folder(mat_folder)
        if raw["parsed_packets"] != expected_count:
            raise AssertionError(
                f"{name}: parsed {raw['parsed_packets']}, expected {expected_count}"
            )
        if len(timestamps) != expected_count:
            raise AssertionError(
                f"{name}: MAT count {len(timestamps)}, expected {expected_count}"
            )
        raw_packets = raw["packets"]
        assert isinstance(raw_packets, list)
        raw_by_time = {round(packet.timestamp, 9): packet for packet in raw_packets}
        differences = []
        for index, timestamp in enumerate(timestamps):
            packet = raw_by_time.get(round(float(timestamp), 9))
            if packet is None:
                raise AssertionError(f"{name}: timestamp {timestamp} missing in raw text")
            differences.append(float(np.max(np.abs(packet.matrix - matrices[index]))))
        max_difference = max(differences)
        if max_difference != 0:
            raise AssertionError(
                f"{name}: raw-to-MAT matrix mismatch {max_difference:.3e}"
            )
        print(
            f"PASS {name}: {expected_count} packets, "
            f"{matrices.shape[2]}x{matrices.shape[3]} BFM, "
            f"MACs={dict(Counter(macs))}, raw-to-MAT max error=0"
        )

    side_expectations = {
        "left": (102, 2),
        "right": (27, 1),
    }
    for label, (expected_count, expected_streams) in side_expectations.items():
        _, matrices, _ = load_folder(ROOT / "experiment" / "v_data" / label)
        if matrices.shape[0] != expected_count or matrices.shape[3] != expected_streams:
            raise AssertionError(
                f"{label}: received shape {matrices.shape}; expected "
                f"({expected_count}, 234, 4, {expected_streams})"
            )
        print(
            f"PASS {label}: shape={matrices.shape} "
            "(raw Wireshark text is not included)"
        )

    print("Artifact integrity checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
