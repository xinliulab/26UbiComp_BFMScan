# BFMScan Artifact

This repository accompanies **BFMScan: Enabling Explicit Angle-Resolved Sensing
via Beamforming Feedback Matrix**. It contains sensing code, recorded
measurements, and numerical plotting inputs for artifact evaluation.

> **Patent pending:** U.S. Provisional Patent Application No. 64/155,826.
> Available for non-commercial academic research only; see [LICENSE](LICENSE).

## Project overview

BFMScan reconstructs angle-resolved spatial spectra from Wi-Fi beamforming
feedback matrices (BFM). It uses MUSIC to separate angular components and
analyzes their temporal variation for device movement, human-side detection,
and respiration monitoring. The respiration pipeline combines temporal FFT,
angle-level motion selection, and PCA waveform aggregation.

The artifact provides two complementary evaluation routes:

1. **Run the system on recorded measurements.** Recompute the three bundled
   application demonstrations in MATLAB and inspect their figures and
   numerical outputs.
2. **Reproduce paper figures from saved results.** Use Python to redraw the
   included evaluation figures from the original numerical plotting inputs.
   This route does not rerun the underlying experiments.

We recommend following this order to inspect the sensing implementation before
the paper's saved aggregate results. The routes are independent: neither reads
the other's generated outputs, and neither requires new data collection.

### Repository structure

```text
BFMScan/
|-- run_all.m                       # Entry point for the three system demos
|-- bfmscan_app1_aod_tracking.m      # Device-motion angle spectrum
|-- bfmscan_side_detection.m        # Left/right human-side detection
|-- bfmscan_breathing_detection.m   # Respiration estimate and belt comparison
|-- matlab/+bfmscan/                # Shared BFM, MUSIC, FFT, ATR, and PCA helpers
|-- experiment/
|   |-- wireshark_data/             # Packet text exports and NeuLog references
|   `-- v_data/                     # Parsed per-packet BFM measurements
|-- parse_bfm.py                    # Packet-export-to-MAT conversion
|-- reproduce_figures.py            # Paper-figure redraw entry point
|-- paper/figure_data.npz           # Frozen numerical plotting inputs
|-- tests/                         # Python regression tests
|-- scripts/validate_artifact.py    # Raw-to-MAT integrity checks
|-- requirements.txt               # Python dependencies
|-- CITATION.cff                   # Machine-readable citation
|-- LICENSE                        # Non-commercial research license; patent pending
`-- results/                       # Generated outputs; excluded from Git
```

## System requirements

Running the three bundled system applications needs only MATLAB. They were
tested with R2024b and use base MATLAB functions without optional toolboxes.
Use Python 3.10 or newer for packet parsing, integrity checks, and paper figures.
The supplied workflows run on the CPU and do not require a GPU. Wi-Fi hardware
and Wireshark are not needed to evaluate the included recordings. The Python
paper-figure route also does not require MATLAB.

Interactive image pop-outs from MATLAB batch mode are supported on Windows
using Windows PowerShell/WPF. For headless evaluation or batch execution on
other platforms, use the save-only command below.

## Quick start

Keep the repository's directory structure intact and run the commands from
its root. All inputs for the two bundled routes are included; no external
workspace, dataset download, or machine-specific path is required.

### 1. Run the three system demonstrations

With MATLAB available on your command line:

```bash
matlab -batch "run_all"
```

This writes the three main figures and their CSV/MAT results to
`results/system/`, prints the input/code/output locations, and opens the three
figures. To save outputs without opening windows:

```bash
matlab -batch "run_all([], 'ShowFigures', false)"
```

See [Evaluation 1](#evaluation-1-run-the-system) for each application's inputs,
processing steps, and expected results. Python installation is not required
for this step.

### 2. Set up Python and check the bundled data

```bash
python -m venv .venv
```

Activate with `.venv\Scripts\activate` on Windows Command Prompt,
`.\.venv\Scripts\Activate.ps1` in PowerShell, or
`source .venv/bin/activate` on Linux/macOS, then run:

```bash
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python scripts/validate_artifact.py
```

The integrity check verifies that the bundled tracking and respiration MAT
matrices match the raw text parser output exactly. Python dependencies are
NumPy, SciPy, and Matplotlib. The tested Python environment is Python 3.12;
dependency ranges are not a lockfile.

### 3. Redraw the paper figures

```bash
python reproduce_figures.py
```

The figures and summary are written to `results/paper/`. See
[Evaluation 2](#evaluation-2-reproduce-paper-figures) for the figure-to-source
mapping and the distinction between saved paper results and newly computed
system outputs.

## Evaluation 1: Run the system

### Three sensing applications

One MATLAB command runs all three applications from packet-level BFM measurements.
It produces exactly three main PNG figures in `results/system/`:

1. `tracking_angle_time.png`: angle-time MUSIC spectrum, labeled +30 to -45 degrees, without a tracking line.
2. `side_detection.png`: left/right angular variation and predicted human side.
3. `respiration_gt_estimate.png`: breathing estimate and NeuLog ground truth together.

CSV/MAT outputs are saved alongside the figures. `run_all` prints each
application's name, raw/parsed input locations, system-code path, and output
locations.

In MATLAB Desktop, the three figures open in separate MATLAB windows. On
Windows, batch mode opens three independent image windows using the built-in
Windows PowerShell/WPF runtime; they remain open after MATLAB exits. No Python
viewer or additional installation is required. On headless systems or other
platforms in batch mode, use `run_all([], 'ShowFigures', false)` to save only.
Use `run_all([], 'Verbose', true)` when full diagnostic output is needed.

| Application | Entry point | Input and processing |
|---|---|---|
| Device-based angular tracking | `bfmscan_app1_aod_tracking.m` | Parsed BFM, MUSIC, peak-angle tracking |
| Left/right human-side detection | `bfmscan_side_detection.m` | Parsed BFM, MUSIC, time-normalized angular variation, left/right energy comparison |
| Respiration monitoring | `bfmscan_breathing_detection.m` | Parsed BFM, MUSIC, 20 Hz interpolation, 30 s FFT, angle-level ATR selection, PCA waveform aggregation |



Run a MATLAB application independently, for example:

```bash
matlab -batch "bfmscan_breathing_detection"
```

Standalone application calls retain their original output folders and
optional diagnostic plots. To select an output directory or suppress desktop
pop-outs:

```matlab
run_all('results/custom_system', 'ShowFigures', false);
```

### Left/right detection from measured BFM

Inputs are the supplied `experiment/v_data/left/` and
`experiment/v_data/right/` MAT files. These contain per-packet timestamps
and BFM matrices, not saved plots or classification scores. Each run recomputes
MUSIC, converts the spectrum to log power, and takes the median absolute
frame-to-frame change divided by elapsed time for adjacent packets no more
than one second apart. The variation is normalized across angles.

The decision score is `(negative-angle energy - positive-angle energy) /
(negative-angle energy + positive-angle energy)`. Positive predicts left;
negative predicts right. Labels are used for display and reporting, not for
computing the score. There is no classifier training, seed search, or
artificial duplication of observations.

`side_detection.png` shows the angular variation and predicted sides without
test-count annotations. `side_features.csv` contains per-angle variation;
`side_summary.csv` contains energy totals, scores, predictions, and acquisition
metadata. `side_results.mat` also retains the newly computed spectra and
timestamps for inspection.


### Breathing ground truth and estimate on one plot

The default NeuLog reference is
`experiment/wireshark_data/8_7/bfm8_7_br.csv`; the BFM input is
`experiment/v_data/BFM_data8_7_br/`.

```matlab
bfmscan_breathing_detection('path/to/mat_folder', 'path/to/belt.csv', ...
    'results/custom_respiration', 'GroundTruthOffsetSeconds', 39.9);
```

### Parse the included Wireshark exports

```bash
python parse_bfm.py experiment/wireshark_data/8_27/ap8_27_move.txt --output-dir results/parsed_tracking --strict
python parse_bfm.py experiment/wireshark_data/8_7/bm8_7_br.txt --output-dir results/parsed_respiration --strict
```

Each input line contains four tab-separated fields: relative timestamp,
transmitter MAC, receiver MAC, and compressed beamforming report hex.
The parser supports the bundled
four-transmit-antenna, one-/two-stream, 234-subcarrier formats; it is not a
general parser for every Wi-Fi report configuration. MAT outputs contain
`packet_timestamps`, `packet_infos` (packet x subcarrier x transmit antenna x
stream), and `ether_srcs`. Existing output chunks are protected unless
`--overwrite` is explicitly passed. MATLAB entry points accept custom input
and output paths; defaults are relative to the code location, not this
machine's drive letters.

## Evaluation 2: Reproduce paper figures

After inspecting the system demonstrations, this route lets reviewers examine
the saved numerical results associated with the paper's evaluation figures.
It can also be run independently in the Python environment:

```bash
python reproduce_figures.py
```

Outputs go to `results/paper/`: PNG and editable SVG figures, plus
`summary.csv`. Use `--output-dir PATH` to choose another destination.
The input is `paper/figure_data.npz`, containing saved arrays from the original
plotting scripts and result files. No raw packet processing or model training
is needed. These figures redraw saved results, not independently rerun experiments;
typography and layout can differ from the manuscript.

## Measurement setup reference

This section documents the existing capture workflow for researchers inspecting
or adapting the parser.

The original setup notes list a Netgear Nighthawk X4S AC2600 AP (four
antennas), TP-Link Wi-Fi 6 USB station, Netgear A6210 monitor-mode sniffer,
and iperf3 reverse traffic from server to station. The supplied spatial code
assumes a four-element, half-wavelength uniform linear array; match the
physical antenna geometry and angle convention before interpreting new data.
Hardware collection was not rerun as part of this software validation.

Install Wireshark/tshark and iperf3 separately for collection. Configure the
sniffer's monitor mode and channel to match the AP, and record the packet
capture on your own experimental network. A compatible capture can be
exported directly into the parser without an intermediate text file:

```bash
tshark -r capture.pcapng -Y "wlan.vht.compressed_beamforming_report" -T fields -e frame.time_relative -e wlan.sa -e wlan.da -e wlan.vht.compressed_beamforming_report | python parse_bfm.py --output-dir results/new_capture
```

Check the parser's accepted/skipped packet counts and the measured packet
rate. Traffic generation does not guarantee a particular feedback rate, and
interpolation cannot recover motion above the native sampling limit.

## Reproducibility scope

Together, the two routes support inspection of the implemented sensing
pipeline and reconstruction of the included paper plots. They provide
different evidence: Evaluation 1 recomputes demonstration outputs from
measurements, while Evaluation 2 redraws saved experimental results.

## Patent

BFMScan is **patent pending**: U.S. Provisional Patent Application
No. 64/155,826, filed September 16, 2026, "Systems and Methods for Explicit
Angle-Resolved Wireless Sensing from Compressed Beamforming Feedback"
(FSU reference 27-029PR).

## License

The code, data, and documentation are available for **non-commercial academic
research, teaching, and artifact evaluation only**. See [LICENSE](LICENSE) for
the full terms. This repository grants no patent rights. For commercial
licensing, contact the Florida State University Office of Commercialization at
commercialization@fsu.edu.

## Citation

If you use BFMScan's code, measurements, or saved evaluation inputs, please cite
the accompanying paper. Machine-readable metadata is provided in
[CITATION.cff](CITATION.cff).

```bibtex
@article{li2026bfmscan,
  title   = {{BFMScan}: Enabling Explicit Angle-Resolved Sensing via Beamforming Feedback Matrix},
  author  = {Li, Bofan and Liu, Zhuoyuan and Ye, Zhankai and Yu, Weikuan and Liu, Xin},
  journal = {Proceedings of the ACM on Interactive, Mobile, Wearable and Ubiquitous Technologies},
  volume  = {10},
  number  = {3},
  year    = {2026},
  doi     = {10.1145/3832009}
}
```
