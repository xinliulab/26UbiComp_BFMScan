function results = bfmscan_side_detection(dataFolders, outputDir, varargin)
%BFMSCAN_SIDE_DETECTION Reproduce the left/right NLoS reflection demo.
%
% This entry point implements the paper's human-side feasibility experiment.
% MUSIC is recomputed from the supplied per-packet BFM measurements.
% No saved plotting spectrum or trained classifier is used.

repoRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(repoRoot, 'matlab'));
if nargin < 1 || isempty(dataFolders)
    dataFolders = {
        fullfile(repoRoot, 'experiment', 'v_data', 'left')
        fullfile(repoRoot, 'experiment', 'v_data', 'right')
        };
end
if nargin < 2 || isempty(outputDir)
    outputDir = fullfile(repoRoot, 'results', 'interaction_side');
end

parser = inputParser;
parser.addParameter('Labels', ["left", "right"], @(x) isstring(x) || iscellstr(x));
parser.addParameter('CarrierFrequencyHz', 5.8e9, @isnumeric);
parser.addParameter('StreamsToUse', 1, @isnumeric);
parser.addParameter('UseLogSpectrum', true, @(x) islogical(x) || isnumeric(x));
parser.addParameter('MaximumPairIntervalSeconds', 1, @isnumeric);
parser.addParameter('MotionBandHz', [0.1, 1.5], @isnumeric);
parser.addParameter('FigureVisible', false, @(x) islogical(x) || isnumeric(x));
parser.addParameter('ExportDiagnostics', true, @islogical);
parser.addParameter('ReportWarnings', false, @islogical);
parser.parse(varargin{:});
options = parser.Results;

if isstring(dataFolders)
    dataFolders = cellstr(dataFolders(:));
end
labels = string(options.Labels(:));
if numel(labels) ~= numel(dataFolders)
    error('BFMScan:LabelCountMismatch', ...
        'The number of Labels must match the number of data folders.');
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

recordingCount = numel(dataFolders);
angleGrid = -90:1:90;
variationByAngle = zeros(recordingCount, numel(angleGrid));
fftAtrByAngle = NaN(recordingCount, numel(angleGrid));
sideScore = NaN(recordingCount, 1);
predictedSide = strings(recordingCount, 1);
packetCount = zeros(recordingCount, 1);
packetRate = NaN(recordingCount, 1);
streamCount = zeros(recordingCount, 1);
negativeEnergyByRecording = zeros(recordingCount, 1);
positiveEnergyByRecording = zeros(recordingCount, 1);
eligiblePairCount = zeros(recordingCount, 1);
recordings = repmat(struct(), recordingCount, 1);

for recordingIndex = 1:recordingCount
    [packetInfos, timestamps, ~, dataMetadata] = ...
        bfmscan.load_bfm_folder(dataFolders{recordingIndex});
    streamsToUse = min(options.StreamsToUse, size(packetInfos, 4));
    [angleSpectrum, validPackets, musicMetadata] = bfmscan.music_spectrum( ...
        packetInfos, ...
        'CarrierFrequencyHz', options.CarrierFrequencyHz, ...
        'StreamsToUse', streamsToUse);

    if ~isequal(angleGrid, musicMetadata.angle_grid_degrees)
        error('BFMScan:UnexpectedAngleGrid', ...
            'The MUSIC angle grid differs from the expected -90:1:90 grid.');
    end
    [variation, eligiblePairCount(recordingIndex)] = local_temporal_variation(angleSpectrum, validPackets, ...
        timestamps, options.UseLogSpectrum, ...
        options.MaximumPairIntervalSeconds);
    variation = variation / max(sum(variation), eps);
    variationByAngle(recordingIndex, :) = variation;

    if options.ExportDiagnostics && dataMetadata.duration_seconds >= 30
        fftResult = bfmscan.angle_time_fft(angleSpectrum, validPackets, ...
            timestamps, angleGrid, ...
            'SamplingRateHz', 20, ...
            'WindowSeconds', 30, ...
            'TargetBandHz', options.MotionBandHz);
        fftAtrByAngle(recordingIndex, :) = fftResult.atr;
    else
        fftResult = struct();
        if options.ExportDiagnostics
            warning('BFMScan:ShortInteractionTrace', ...
                '%s is shorter than the 30 s FFT window.', dataFolders{recordingIndex});
        end
    end

    negativeEnergy = sum(variation(angleGrid < 0));
    positiveEnergy = sum(variation(angleGrid > 0));
    negativeEnergyByRecording(recordingIndex) = negativeEnergy;
    positiveEnergyByRecording(recordingIndex) = positiveEnergy;
    sideScore(recordingIndex) = (negativeEnergy - positiveEnergy) ...
        / max(negativeEnergy + positiveEnergy, eps);
    if sideScore(recordingIndex) >= 0
        predictedSide(recordingIndex) = "left";
    else
        predictedSide(recordingIndex) = "right";
    end

    packetCount(recordingIndex) = dataMetadata.packet_count;
    packetRate(recordingIndex) = dataMetadata.median_packet_rate_hz;
    streamCount(recordingIndex) = dataMetadata.spatial_stream_count;
    recordings(recordingIndex).label = labels(recordingIndex);
    recordings(recordingIndex).data = dataMetadata;
    recordings(recordingIndex).music = musicMetadata;
    recordings(recordingIndex).variation = variation;
    recordings(recordingIndex).fft = fftResult;
    recordings(recordingIndex).angle_spectrum = angleSpectrum;
    recordings(recordingIndex).valid_packets = validPackets;
    recordings(recordingIndex).timestamps = timestamps;
end

if options.ReportWarnings && numel(unique(streamCount)) > 1
    warning('BFMScan:ConfoundedSideData', ...
        ['Side recordings use different spatial-stream counts (%s). ' ...
        'Do not interpret these two traces as an accuracy evaluation.'], ...
        mat2str(unique(streamCount).'));
end
if options.ReportWarnings && max(packetRate) / min(packetRate) > 2
    warning('BFMScan:ConfoundedPacketRates', ...
        ['Side recordings have substantially different packet rates ' ...
        '(%.2f-%.2f Hz).'], min(packetRate), max(packetRate));
end

visibility = local_visibility(options.FigureVisible);
figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Name', 'BFMScan left/right human-side detection', 'Position', [100 100 1100 420]);
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plot(angleGrid, variationByAngle.', 'LineWidth', 1.7);
xline(0, '--k'); grid on;
xlabel('Signed AoD (degrees)'); ylabel('Normalized temporal variation');
title('Motion-induced angular variation');
legend(compose('Human %s', labels), 'Location', 'best');
nexttile;
bar(sideScore, 'FaceColor', [0.25 0.48 0.75]);
yline(0, '--k'); grid on;
xticks(1:recordingCount); xticklabels(compose('Human %s', labels));
ylabel('Signed left/right variation-energy score');
title('Positive: left | Negative: right');
bound = max(0.3, 1.6 * max(abs(sideScore)));
ylim([-bound, bound]);
for recordingIndex = 1:recordingCount
    direction = sign(sideScore(recordingIndex));
    if direction == 0, direction = 1; end
    text(recordingIndex, sideScore(recordingIndex) + direction * 0.12 * bound, ...
        sprintf('Predicted %s', predictedSide(recordingIndex)), ...
        'HorizontalAlignment', 'center');
end
bfmscan.export_figure(figureHandle, fullfile(outputDir, 'side_detection.png'));
close(figureHandle);

if options.ExportDiagnostics
figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Name', 'BFMScan side variation');
plot(angleGrid, variationByAngle.', 'LineWidth', 1.5);
xline(0, '--k');
grid on;
xlabel('Signed AoD (degrees; broadside = 0)');
ylabel('Normalized temporal variation');
legend(labels, 'Location', 'best');
title('NLoS human-side angular variation');
bfmscan.export_figure(figureHandle, ...
    fullfile(outputDir, 'side_variation_by_angle.png'));
close(figureHandle);

figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Name', 'BFMScan side score');
bar(sideScore);
yline(0, '--k');
grid on;
xticks(1:recordingCount);
xticklabels(labels);
ylabel('(negative-angle energy - positive-angle energy) / total');
title('Human-side score (positive predicts left)');
bfmscan.export_figure(figureHandle, ...
    fullfile(outputDir, 'side_score.png'));
close(figureHandle);

if any(isfinite(fftAtrByAngle(:)))
    figureHandle = figure('Color', 'w', 'Visible', visibility, ...
        'Name', 'BFMScan interaction FFT');
    plot(angleGrid, fftAtrByAngle.', 'LineWidth', 1.5);
    xline(0, '--k');
    grid on;
    xlabel('Signed AoD (degrees; broadside = 0)');
    ylabel('FFT target-to-noise ratio (ATR)');
    legend(labels, 'Location', 'best');
    title(sprintf('Motion-band FFT diagnostic (%.2f-%.2f Hz)', ...
        options.MotionBandHz(1), options.MotionBandHz(2)));
    bfmscan.export_figure(figureHandle, ...
        fullfile(outputDir, 'side_fft_atr.png'));
    close(figureHandle);
end
end

summary = table(labels, packetCount, packetRate, streamCount, ...
    eligiblePairCount, negativeEnergyByRecording, positiveEnergyByRecording, sideScore, predictedSide, ...
    'VariableNames', {'recording_label', 'packet_count', ...
    'median_packet_rate_hz', 'spatial_stream_count', ...
    'eligible_packet_pairs', 'negative_angle_energy', 'positive_angle_energy', ...
    'side_score', 'predicted_side'});
writetable(summary, fullfile(outputDir, 'side_summary.csv'));
featureLabels = repelem(labels, numel(angleGrid));
featureAngles = repmat(angleGrid(:), recordingCount, 1);
featureVariation = reshape(variationByAngle.', [], 1);
features = table(featureLabels, featureAngles, featureVariation, ...
    'VariableNames', {'recording_label', 'angle_degrees', 'normalized_temporal_variation'});
writetable(features, fullfile(outputDir, 'side_features.csv'));

results = struct();
results.application = "human-side identification feasibility";
results.angle_grid_degrees = angleGrid;
results.variation_by_angle = variationByAngle;
results.fft_atr_by_angle = fftAtrByAngle;
results.summary = summary;
results.recordings = recordings;
save(fullfile(outputDir, 'side_results.mat'), 'results', '-v7.3');

disp(summary);
end


function [variation, eligiblePairCount] = local_temporal_variation(spectrum, validPackets, ...
    timestamps, useLogSpectrum, maximumPairInterval)
values = spectrum(validPackets, :);
time = timestamps(validPackets);
if useLogSpectrum
    values = 10 * log10(values + 1e-12);
end
deltaTime = diff(time);
goodPairs = deltaTime > 0 & deltaTime <= maximumPairInterval;
eligiblePairCount = sum(goodPairs);
if ~any(goodPairs)
    error('BFMScan:NoTemporalPairs', ...
        'No adjacent packets satisfy the temporal interval constraint.');
end
deltaValues = diff(values, 1, 1);
pairVariation = abs(deltaValues(goodPairs, :)) ./ deltaTime(goodPairs);
variation = median(pairVariation, 1);
end


function visibility = local_visibility(isVisible)
if isVisible
    visibility = 'on';
else
    visibility = 'off';
end
end
