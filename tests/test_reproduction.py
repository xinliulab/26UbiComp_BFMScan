"""Regression checks for frozen paper plotting inputs."""
import json
from pathlib import Path
import unittest

import numpy as np
from reproduce_figures import normalize

ROOT = Path(__file__).resolve().parents[1]


class ReproductionTests(unittest.TestCase):
    def test_frozen_paper_values(self):
        with np.load(ROOT / 'paper' / 'figure_data.npz', allow_pickle=False) as data:
            for key in ['los_cm', 'wall_cm']:
                np.testing.assert_allclose(data[key].sum(axis=1), 100)
            np.testing.assert_allclose(data['side_values'], [93.5, 98, 99.2, 97.2, 96.26])
            np.testing.assert_allclose([np.median(data[f'users_{i}']) for i in range(3)],
                                       [.253, .2449, .6325])
            self.assertTrue(np.all(np.diff(data['wave_x']) > 0))
            self.assertEqual(data['wave_x'].shape, data['wave_gt'].shape)
            self.assertEqual(data['wave_x'].shape, data['wave_ours'].shape)
            self.assertGreaterEqual(len(json.loads(str(data['source_sha256_json']))), 10)

    def test_normalization_constant_and_range(self):
        np.testing.assert_array_equal(normalize([3, 3, 3]), [0, 0, 0])
        np.testing.assert_allclose(normalize([-2, 0, 2]), [0, .5, 1])


if __name__ == '__main__':
    unittest.main()
