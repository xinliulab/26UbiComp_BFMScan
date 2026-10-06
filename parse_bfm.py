"""Parse IEEE 802.11ac compressed beamforming reports into MATLAB files.

The input format is the four-column, tab-separated output produced by the
``tshark`` command documented in README.md:

    frame.time_relative  wlan.sa  wlan.da  wlan.vht.compressed_beamforming_report

This parser supports the 4x1 and 4x2 feedback formats used by BFMScan.  It
does not depend on a machine-specific path and it always flushes the final
partial chunk.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Iterator, Sequence, TextIO

import numpy as np
from scipy.io import savemat


NSUBC_VALID = 234
NR = 4
PSI_BITS = 4
PHI_BITS = 6

_ANGLE_WIDTHS = {
    1: (6, 6, 6, 4, 4, 4),
    2: (6, 6, 6, 4, 4, 4, 6, 6, 4, 4),
}


class BFMParseError(ValueError):
    """Raised when a feedback report cannot be decoded safely."""


@dataclass
class ParsedPacket:
    timestamp: float
    source_mac: str
    destination_mac: str
    snr: tuple[float, ...]
    matrix: np.ndarray


@dataclass
class ParseStats:
    input_lines: int = 0
    parsed_packets: int = 0
    skipped_lines: int = 0
    written_files: int = 0
    stream_counts: dict[int, int] = field(default_factory=dict)
    source_counts: dict[str, int] = field(default_factory=dict)
    max_semiunitary_error: float = 0.0
    errors: list[str] = field(default_factory=list)

    def record_error(self, line_number: int, message: str) -> None:
        self.skipped_lines += 1
        if len(self.errors) < 10:
            self.errors.append(f"line {line_number}: {message}")


def _expected_report_bytes(streams: int) -> int:
    payload_bits = NSUBC_VALID * sum(_ANGLE_WIDTHS[streams])
    return streams + math.ceil(payload_bits / 8)


def infer_stream_count(report_hex: str) -> int:
    """Infer 1 or 2 spatial streams from the encoded report length."""

    try:
        report_bytes = len(bytes.fromhex(report_hex))
    except ValueError as exc:
        raise BFMParseError(f"report is not valid hexadecimal: {exc}") from exc

    candidates = []
    for streams in (1, 2):
        expected = _expected_report_bytes(streams)
        trailing = report_bytes - expected
        if 0 <= trailing <= 8:
            candidates.append((trailing, streams))
    if not candidates:
        expected = ", ".join(
            f"{streams} stream(s): {_expected_report_bytes(streams)} bytes"
            for streams in (1, 2)
        )
        raise BFMParseError(
            f"unexpected report length {report_bytes} bytes (expected {expected})"
        )
    return min(candidates)[1]


def _unpack_quantized_angles(payload: bytes, streams: int) -> np.ndarray:
    widths = _ANGLE_WIDTHS[streams]
    required_bits = NSUBC_VALID * sum(widths)
    if len(payload) * 8 < required_bits:
        raise BFMParseError(
            f"payload has {len(payload) * 8} bits; {required_bits} are required"
        )

    # IEEE feedback angles are packed least-significant bit first.  This
    # representation mirrors Wireshark's byte-oriented hexadecimal output.
    bits = "".join(f"{byte:08b}"[::-1] for byte in payload)
    result = np.empty((NSUBC_VALID, len(widths)), dtype=np.float64)
    cursor = 0
    for subcarrier in range(NSUBC_VALID):
        for angle_index, width in enumerate(widths):
            encoded = bits[cursor : cursor + width]
            result[subcarrier, angle_index] = int(encoded[::-1], 2)
            cursor += width
    return result


def decompress(
    quantized_angles: np.ndarray,
    streams: int,
    *,
    round_decimals: int | None = 4,
) -> np.ndarray:
    """Reconstruct a 234 x 4 x Nc semi-unitary beamforming matrix."""

    angles = np.asarray(quantized_angles, dtype=np.float64)
    expected_columns = len(_ANGLE_WIDTHS[streams])
    if angles.shape != (NSUBC_VALID, expected_columns):
        raise BFMParseError(
            f"angle array has shape {angles.shape}; "
            f"expected {(NSUBC_VALID, expected_columns)}"
        )

    const1_psi = 1 / (2 ** (PSI_BITS + 1))
    const2_psi = 1 / (2 ** (PSI_BITS + 2))
    const1_phi = 1 / (2 ** (PHI_BITS - 1))
    const2_phi = 1 / (2**PHI_BITS)

    phi_11 = np.pi * (const2_phi + const1_phi * angles[:, 0])
    phi_21 = np.pi * (const2_phi + const1_phi * angles[:, 1])
    phi_31 = np.pi * (const2_phi + const1_phi * angles[:, 2])
    psi_21 = np.pi * (const2_psi + const1_psi * angles[:, 3])
    psi_31 = np.pi * (const2_psi + const1_psi * angles[:, 4])
    psi_41 = np.pi * (const2_psi + const1_psi * angles[:, 5])

    matrices = np.zeros((NSUBC_VALID, NR, streams), dtype=np.complex128)
    identity = np.eye(NR, streams, dtype=np.complex128)

    for index in range(NSUBC_VALID):
        d1 = np.diag(
            [
                np.exp(1j * phi_11[index]),
                np.exp(1j * phi_21[index]),
                np.exp(1j * phi_31[index]),
                1,
            ]
        )
        g21 = np.array(
            [
                [np.cos(psi_21[index]), np.sin(psi_21[index]), 0, 0],
                [-np.sin(psi_21[index]), np.cos(psi_21[index]), 0, 0],
                [0, 0, 1, 0],
                [0, 0, 0, 1],
            ]
        )
        g31 = np.array(
            [
                [np.cos(psi_31[index]), 0, np.sin(psi_31[index]), 0],
                [0, 1, 0, 0],
                [-np.sin(psi_31[index]), 0, np.cos(psi_31[index]), 0],
                [0, 0, 0, 1],
            ]
        )
        g41 = np.array(
            [
                [np.cos(psi_41[index]), 0, 0, np.sin(psi_41[index])],
                [0, 1, 0, 0],
                [0, 0, 1, 0],
                [-np.sin(psi_41[index]), 0, 0, np.cos(psi_41[index])],
            ]
        )
        value = d1 @ g21.T @ g31.T @ g41.T

        if streams == 2:
            phi_22 = np.pi * (const2_phi + const1_phi * angles[index, 6])
            phi_32 = np.pi * (const2_phi + const1_phi * angles[index, 7])
            psi_32 = np.pi * (const2_psi + const1_psi * angles[index, 8])
            psi_42 = np.pi * (const2_psi + const1_psi * angles[index, 9])
            d2 = np.diag([1, np.exp(1j * phi_22), np.exp(1j * phi_32), 1])
            g32 = np.array(
                [
                    [1, 0, 0, 0],
                    [0, np.cos(psi_32), np.sin(psi_32), 0],
                    [0, -np.sin(psi_32), np.cos(psi_32), 0],
                    [0, 0, 0, 1],
                ]
            )
            g42 = np.array(
                [
                    [1, 0, 0, 0],
                    [0, np.cos(psi_42), 0, np.sin(psi_42)],
                    [0, 0, 1, 0],
                    [0, -np.sin(psi_42), 0, np.cos(psi_42)],
                ]
            )
            value = value @ d2 @ g32.T @ g42.T

        matrices[index] = value @ identity

    if round_decimals is not None:
        matrices = np.round(matrices, decimals=round_decimals)
    return matrices


def parse_report(
    report_hex: str, streams: int | None = None
) -> tuple[tuple[float, ...], np.ndarray]:
    """Decode SNR bytes and the compressed feedback matrix from one report."""

    compact = "".join(report_hex.split())
    if not compact:
        raise BFMParseError("empty beamforming report")
    try:
        raw = bytes.fromhex(compact)
    except ValueError as exc:
        raise BFMParseError(f"report is not valid hexadecimal: {exc}") from exc

    stream_count = streams or infer_stream_count(compact)
    expected_bytes = _expected_report_bytes(stream_count)
    if len(raw) < expected_bytes:
        raise BFMParseError(
            f"report has {len(raw)} bytes; {expected_bytes} are required for "
            f"{stream_count} stream(s)"
        )

    snr = tuple(raw[index] * 0.25 + 22 for index in range(stream_count))
    payload = raw[stream_count:expected_bytes]
    quantized = _unpack_quantized_angles(payload, stream_count)
    return snr, decompress(quantized, stream_count)


def parse_tshark_line(
    line: str, streams: int | None = None
) -> ParsedPacket:
    fields = line.rstrip("\r\n").split("\t")
    if len(fields) != 4:
        raise BFMParseError(f"expected 4 tab-separated fields, received {len(fields)}")
    timestamp_text, source_mac, destination_mac, report_hex = fields
    try:
        timestamp = float(timestamp_text)
    except ValueError as exc:
        raise BFMParseError(f"invalid timestamp {timestamp_text!r}") from exc
    snr, matrix = parse_report(report_hex, streams)
    return ParsedPacket(
        timestamp=timestamp,
        source_mac=source_mac.lower(),
        destination_mac=destination_mac.lower(),
        snr=snr,
        matrix=matrix,
    )


def _semiunitary_error(matrix: np.ndarray) -> float:
    gram = np.swapaxes(matrix.conj(), -2, -1) @ matrix
    identity = np.eye(matrix.shape[-1], dtype=np.complex128)
    return float(np.max(np.linalg.norm(gram - identity, axis=(-2, -1))))


def _write_chunk(
    packets: Sequence[ParsedPacket], output_dir: Path, stats: ParseStats
) -> Path:
    if not packets:
        raise ValueError("cannot write an empty packet chunk")
    stream_count = packets[0].matrix.shape[-1]
    data = {
        "packet_timestamps": np.asarray(
            [packet.timestamp for packet in packets], dtype=np.float64
        ),
        "packet_snrs1": np.asarray(
            [packet.snr[0] for packet in packets], dtype=np.float64
        ),
        "ether_srcs": np.asarray([packet.source_mac for packet in packets]),
        "packet_infos": np.stack([packet.matrix for packet in packets], axis=0),
    }
    if stream_count == 2:
        data["packet_snrs2"] = np.asarray(
            [packet.snr[1] for packet in packets], dtype=np.float64
        )

    last_timestamp = packets[-1].timestamp
    path = output_dir / f"packets_{last_timestamp:.9f}.mat"
    savemat(path, data, do_compression=True)
    stats.written_files += 1
    return path


def convert_lines(
    lines: Iterable[str],
    output_dir: Path,
    *,
    streams: int | None = None,
    chunk_seconds: float = 5.0,
    source_mac: str | None = None,
    strict: bool = False,
) -> ParseStats:
    """Convert tshark lines and return detailed parsing statistics."""

    if chunk_seconds <= 0:
        raise ValueError("chunk_seconds must be positive")
    output_dir.mkdir(parents=True, exist_ok=True)
    if any(output_dir.glob("packets_*.mat")):
        raise FileExistsError(
            f"{output_dir} already contains packets_*.mat files; "
            "choose a new directory or pass --overwrite"
        )

    wanted_mac = source_mac.lower() if source_mac else None
    stats = ParseStats()
    buffer: list[ParsedPacket] = []
    chunk_start: float | None = None
    active_stream_count: int | None = streams

    for line_number, line in enumerate(lines, start=1):
        stats.input_lines += 1
        if not line.strip():
            continue
        try:
            packet = parse_tshark_line(line, streams)
            packet_streams = packet.matrix.shape[-1]
            if wanted_mac and packet.source_mac != wanted_mac:
                continue
            if active_stream_count is None:
                active_stream_count = packet_streams
            if packet_streams != active_stream_count:
                raise BFMParseError(
                    f"stream count changed from {active_stream_count} to "
                    f"{packet_streams}; split heterogeneous captures"
                )
        except (BFMParseError, ValueError) as exc:
            stats.record_error(line_number, str(exc))
            if strict:
                raise
            continue

        stats.parsed_packets += 1
        stats.stream_counts[packet_streams] = (
            stats.stream_counts.get(packet_streams, 0) + 1
        )
        stats.source_counts[packet.source_mac] = (
            stats.source_counts.get(packet.source_mac, 0) + 1
        )
        stats.max_semiunitary_error = max(
            stats.max_semiunitary_error, _semiunitary_error(packet.matrix)
        )
        buffer.append(packet)
        if chunk_start is None:
            chunk_start = packet.timestamp
        if packet.timestamp - chunk_start >= chunk_seconds:
            _write_chunk(buffer, output_dir, stats)
            buffer = []
            chunk_start = None

    if buffer:
        _write_chunk(buffer, output_dir, stats)
    return stats


def _open_input(path: str | None) -> tuple[TextIO, bool]:
    if path is None or path == "-":
        return sys.stdin, False
    return Path(path).open("r", encoding="utf-8"), True


def _build_argument_parser(default_streams: int | None) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert tshark BFM text into chunked MATLAB files."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="-",
        help="input .txt file, or '-' for stdin (default: stdin)",
    )
    parser.add_argument(
        "--output-dir",
        "-o",
        required=True,
        type=Path,
        help="directory for packets_*.mat files",
    )
    parser.add_argument(
        "--streams",
        choices=("auto", "1", "2"),
        default=str(default_streams) if default_streams else "auto",
        help="number of spatial streams (default: infer from report length)",
    )
    parser.add_argument(
        "--chunk-seconds",
        type=float,
        default=5.0,
        help="maximum trace duration per MAT chunk (default: 5)",
    )
    parser.add_argument(
        "--source-mac",
        help="only retain packets from this transmitter MAC address",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="stop at the first malformed line instead of skipping it",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="replace existing packets_*.mat files in the output directory",
    )
    return parser


def main(
    argv: Sequence[str] | None = None, *, default_streams: int | None = None
) -> int:
    args = _build_argument_parser(default_streams).parse_args(argv)
    stream_count = None if args.streams == "auto" else int(args.streams)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    existing = list(args.output_dir.glob("packets_*.mat"))
    if existing:
        if not args.overwrite:
            raise FileExistsError(
                f"{args.output_dir} contains {len(existing)} MAT files; "
                "use --overwrite or choose a new output directory"
            )
        for path in existing:
            path.unlink()

    handle, should_close = _open_input(args.input)
    try:
        stats = convert_lines(
            handle,
            args.output_dir,
            streams=stream_count,
            chunk_seconds=args.chunk_seconds,
            source_mac=args.source_mac,
            strict=args.strict,
        )
    finally:
        if should_close:
            handle.close()

    print(
        "Parsed "
        f"{stats.parsed_packets}/{stats.input_lines} lines; "
        f"skipped {stats.skipped_lines}; wrote {stats.written_files} MAT files "
        f"to {args.output_dir}"
    )
    print(f"Source MAC counts: {stats.source_counts}")
    print(f"Spatial-stream counts: {stats.stream_counts}")
    print(f"Max ||V^H V - I||_F: {stats.max_semiunitary_error:.3e}")
    if stats.errors:
        print("First parsing warnings:", file=sys.stderr)
        for message in stats.errors:
            print(f"  {message}", file=sys.stderr)
    return 0 if stats.parsed_packets else 2


if __name__ == "__main__":
    raise SystemExit(main())
