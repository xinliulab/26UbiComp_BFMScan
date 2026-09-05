from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from parse_bfm import BFMParseError, convert_lines, parse_report, parse_tshark_line


ROOT = Path(__file__).resolve().parents[1]
RAW_TRACKING = (
    ROOT / "experiment" / "wireshark_data" / "8_27" / "ap8_27_move.txt"
)
MAT_TRACKING = ROOT / "experiment" / "v_data" / "ap8_27_move"


def _find_existing_packet(timestamp: float) -> np.ndarray:
    for path in MAT_TRACKING.glob("packets_*.mat"):
        loaded = loadmat(path, squeeze_me=False)
        timestamps = np.asarray(loaded["packet_timestamps"]).reshape(-1)
        matches = np.flatnonzero(
            np.isclose(timestamps.astype(float), timestamp, atol=1e-12)
        )
        if matches.size:
            return np.asarray(loaded["packet_infos"])[int(matches[0])]
    raise AssertionError(f"timestamp {timestamp} not found in checked-in MAT data")


class ParserTests(unittest.TestCase):
    def test_first_tracking_packet_matches_checked_in_matrix(self) -> None:
        with RAW_TRACKING.open(encoding="utf-8") as stream:
            packet = parse_tshark_line(stream.readline())
        expected = _find_existing_packet(packet.timestamp)
        self.assertEqual(packet.matrix.shape, (234, 4, 2))
        np.testing.assert_array_equal(packet.matrix, expected)

    def test_reconstructed_columns_are_semiunitary(self) -> None:
        with RAW_TRACKING.open(encoding="utf-8") as stream:
            report = stream.readline().rstrip("\n").split("\t")[3]
        _, matrix = parse_report(report)
        gram = np.swapaxes(matrix.conj(), -2, -1) @ matrix
        error = np.max(np.linalg.norm(gram - np.eye(2), axis=(-2, -1)))
        self.assertLess(error, 3e-4)

    def test_final_partial_chunk_is_flushed(self) -> None:
        with RAW_TRACKING.open(encoding="utf-8") as stream:
            lines = [stream.readline(), stream.readline()]
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            output = Path(directory)
            stats = convert_lines(lines, output, chunk_seconds=5)
            files = list(output.glob("packets_*.mat"))
            self.assertEqual(stats.parsed_packets, 2)
            self.assertEqual(stats.written_files, 1)
            self.assertEqual(len(files), 1)
            loaded = loadmat(files[0], squeeze_me=False)
            self.assertEqual(loaded["packet_infos"].shape, (2, 234, 4, 2))

    def test_empty_report_is_rejected(self) -> None:
        with self.assertRaises(BFMParseError):
            parse_report("")


if __name__ == "__main__":
    unittest.main()
