function results = bfmscan_breathing_detection(dataFolder, groundTruthCsv, outputDir, varargin)
%BFMSCAN_BREATHING_DETECTION Reproduce the angle-time respiration demo.
%
% The default path implements the paper's 20 Hz interpolation, 30 s FFT,
% angle-level ATR selection, and PCA aggregation. The bundled recording
% uses the historical NeuLog/BFM ground-truth time mapping.

repoRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(repoRoot, 'matlab'));
if nargin < 1 || isempty(dataFolder)
    dataFolder = fullfile(repoRoot, 'experiment', 'v_data', 'BFM_data8_7_br');
end
if nargin < 2 || isempty(groundTruthCsv)
    groundTruthCsv = fullfile(repoRoot, 'experiment', ...
        'wireshark_data', '8_7', 'bfm8_7_br.csv');
end
if nargin < 3 || isempty(outputDir)
    outputDir = fullfile(repoRoot, 'results', 'respiration');
end

parser = inputParser;
parser.addParameter('CarrierFrequencyHz', 5.765e9, @isnumeric);
parser.addParameter('StreamsToUse', 2, @isnumeric);
parser.addParameter('SamplingRateHz', 20, @isnumeric);
parser.addParameter('FftWindowSeconds', 30, @isnumeric);
parser.addParameter('RespirationBandHz', [0.15, 0.4], @isnumeric);
parser.addParameter('SpatialThresholdRelative', 0.2, @isnumeric);
parser.addParameter('AtrThresholdRelative', 0.5, @isnumeric);
parser.addParameter('MinimumClusterBins', 3, @isnumeric);
parser.addParameter('MaximumClusters', 3, @isnumeric);
parser.addParameter('GroundTruthOffsetSeconds', [], @isnumeric);
parser.addParameter('FigureVisible', false, @(x) islogical(x) || isnumeric(x));
parser.addParameter('ExportDiagnostics', true, @islogical);
parser.parse(varargin{:});
options = parser.Results;
if isempty(options.GroundTruthOffsetSeconds)
    bundledCsv = fullfile(repoRoot, 'experiment', 'wireshark_data', ...
        '8_7', 'bfm8_7_br.csv');
    bundledData = fullfile(repoRoot, 'experiment', 'v_data', 'BFM_data8_7_br');
    if strcmp(char(groundTruthCsv), bundledCsv) && strcmp(char(dataFolder), bundledData)
        % Existing analysis: belt samples 500:1100 (49.9:109.9 s)
        % correspond to BFM time 10:70 s. No lag optimization is applied.
        options.GroundTruthOffsetSeconds = 39.9;
    else
        options.GroundTruthOffsetSeconds = NaN;
    end
end

if ~isfolder(outputDir)
    mkdir(outputDir);
end
[packetInfos, timestamps, ~, dataMetadata] = ...
    bfmscan.load_bfm_folder(dataFolder);
[angleSpectrum, validPackets, musicMetadata] = bfmscan.music_spectrum( ...
    packetInfos, ...
    'CarrierFrequencyHz', options.CarrierFrequencyHz, ...
    'StreamsToUse', options.StreamsToUse);
angleGrid = musicMetadata.angle_grid_degrees;

fftResult = bfmscan.angle_time_fft(angleSpectrum, validPackets, ...
    timestamps, angleGrid, ...
    'SamplingRateHz', options.SamplingRateHz, ...
    'WindowSeconds', options.FftWindowSeconds, ...
    'TargetBandHz', options.RespirationBandHz);

meanSpatialSpectrum = mean(angleSpectrum(validPackets, :), 1);
spatialMask = meanSpatialSpectrum >= options.SpatialThresholdRelative ...
    * max(meanSpatialSpectrum);
motionMask = fftResult.atr >= options.AtrThresholdRelative ...
    * max(fftResult.atr);
spatialClusters = bfmscan.contiguous_clusters(spatialMask, ...
    options.MinimumClusterBins);

candidateClusters = {};
candidateScores = [];
for clusterIndex = 1:numel(spatialClusters)
    members = spatialClusters{clusterIndex};
    selected = members(motionMask(members));
    if ~isempty(selected)
        candidateClusters{end + 1} = selected; %#ok<AGROW>
        candidateScores(end + 1) = max(fftResult.atr(selected)); %#ok<AGROW>
    end
end

if isempty(candidateClusters)
    warning('BFMScan:AtrSpatialFallback', ...
        ['No spatial cluster passed the ATR threshold; grouping contiguous ' ...
        'high-ATR angles directly.']);
    candidateClusters = bfmscan.contiguous_clusters(motionMask, 1);
    candidateScores = zeros(1, numel(candidateClusters));
    for clusterIndex = 1:numel(candidateClusters)
        candidateScores(clusterIndex) = max( ...
            fftResult.atr(candidateClusters{clusterIndex}));
    end
end
if isempty(candidateClusters)
    [~, bestAngle] = max(fftResult.atr);
    candidateClusters = {max(1, bestAngle - 1):min(numel(angleGrid), bestAngle + 1)};
    candidateScores = fftResult.atr(bestAngle);
end

[~, scoreOrder] = sort(candidateScores, 'descend');
scoreOrder = scoreOrder(1:min(options.MaximumClusters, numel(scoreOrder)));
candidateClusters = candidateClusters(scoreOrder);
candidateScores = candidateScores(scoreOrder);
centroids = zeros(numel(candidateClusters), 1);
for clusterIndex = 1:numel(candidateClusters)
    members = candidateClusters{clusterIndex};
    weights = meanSpatialSpectrum(members);
    centroids(clusterIndex) = sum(angleGrid(members) .* weights) ...
        / max(sum(weights), eps);
end
[centroids, angleOrder] = sort(centroids);
candidateClusters = candidateClusters(angleOrder);
candidateScores = candidateScores(angleOrder);

clusterCount = numel(candidateClusters);
clusterSignals = zeros(numel(fftResult.time_seconds), clusterCount);
dominantFrequencyHz = NaN(clusterCount, 1);
respirationRateBpm = NaN(clusterCount, 1);
minimumAngle = NaN(clusterCount, 1);
maximumAngle = NaN(clusterCount, 1);
selectedBinCount = zeros(clusterCount, 1);
for clusterIndex = 1:clusterCount
    members = candidateClusters{clusterIndex};
    clusterSignals(:, clusterIndex) = bfmscan.pca_signal( ...
        fftResult.signals(:, members));
    dominantFrequencyHz(clusterIndex) = bfmscan.dominant_frequency( ...
        clusterSignals(:, clusterIndex), options.SamplingRateHz, ...
        options.RespirationBandHz);
    respirationRateBpm(clusterIndex) = 60 * dominantFrequencyHz(clusterIndex);
    minimumAngle(clusterIndex) = min(angleGrid(members));
    maximumAngle(clusterIndex) = max(angleGrid(members));
    selectedBinCount(clusterIndex) = numel(members);
end

groundTruthRateBpm = NaN;
waveformCosineSimilarity = NaN(clusterCount, 1);
comparison = table();
comparisonPolarity = NaN(clusterCount, 1);
if isfile(groundTruthCsv)
    groundTruth = bfmscan.load_neulog_csv(groundTruthCsv);
    groundTruthRateHz = bfmscan.dominant_frequency( ...
        groundTruth.respiration, 10, options.RespirationBandHz);
    groundTruthRateBpm = 60 * groundTruthRateHz;

    if isfinite(options.GroundTruthOffsetSeconds)
        queryTime = fftResult.absolute_time_seconds ...
            + options.GroundTruthOffsetSeconds;
        inRange = queryTime >= groundTruth.time_seconds(1) ...
            & queryTime <= groundTruth.time_seconds(end);
        if sum(inRange) >= options.SamplingRateHz * 10
            reference = interp1(groundTruth.time_seconds, ...
                groundTruth.respiration, queryTime(inRange), 'linear');
            reference = detrend(reference, 0);
            reference = reference / max(norm(reference), eps);
            for clusterIndex = 1:clusterCount
                estimate = detrend(clusterSignals(inRange, clusterIndex), 0);
                estimate = estimate / max(norm(estimate), eps);
                % PCA sign is arbitrary, so compare absolute similarity.
                waveformCosineSimilarity(clusterIndex) = ...
                    abs(dot(estimate, reference));
            end
            comparisonTime = fftResult.absolute_time_seconds(inRange);
            gtAmplitude = (reference - mean(reference)) / max(std(reference), eps);
            estimateAmplitude = clusterSignals(inRange, :);
            for clusterIndex = 1:clusterCount
                value = estimateAmplitude(:, clusterIndex);
                value = (value - mean(value)) / max(std(value), eps);
                % Display polarity is arbitrary for PCA; record it explicitly.
                polarity = sign(dot(value, gtAmplitude));
                if polarity == 0, polarity = 1; end
                comparisonPolarity(clusterIndex) = polarity;
                estimateAmplitude(:, clusterIndex) = polarity * value;
            end
            comparison = array2table([comparisonTime, gtAmplitude, estimateAmplitude], ...
                'VariableNames', [{'bfm_time_seconds', 'ground_truth_zscore'}, ...
                cellstr(compose('estimate_cluster_%d_zscore', 1:clusterCount))]);
            writetable(comparison, fullfile(outputDir, 'respiration_gt_estimate.csv'));
            figureHandle = figure('Color', 'w', 'Visible', ...
                local_visibility(options.FigureVisible), 'Position', [100 100 1000 450]);
            plot(comparisonTime, gtAmplitude, 'k-', 'LineWidth', 1.5);
            hold on;
            plot(comparisonTime, estimateAmplitude, 'LineWidth', 1.3);
            hold off; grid on; axis tight;
            xlabel('BFM time (s)'); ylabel('Amplitude (z-score)');
            legend(['NeuLog ground truth', compose('BFMScan cluster %d', 1:clusterCount)], ...
                'Location', 'northoutside', 'Orientation', 'horizontal');
            title(sprintf('Respiration comparison | belt time = BFM time + %.1f s', ...
                options.GroundTruthOffsetSeconds));
            bfmscan.export_figure(figureHandle, ...
                fullfile(outputDir, 'respiration_gt_estimate.png'));
            close(figureHandle);
        else
            warning('BFMScan:GroundTruthNoOverlap', ...
                'The supplied ground-truth offset yields less than 10 s overlap.');
        end
    else
        warning('BFMScan:GroundTruthNotSynchronized', ...
            ['Ground truth is present but no synchronization offset is ' ...
            'documented. Rate is reported; waveform cosine similarity is skipped.']);
    end
end

if options.ExportDiagnostics
visibility = local_visibility(options.FigureVisible);
relativePacketTime = timestamps - timestamps(1);
figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Name', 'BFMScan respiration angle-time spectrum');
imagesc(relativePacketTime(validPackets), angleGrid, ...
    angleSpectrum(validPackets, :).');
axis xy tight;
colormap(turbo);
colorbarHandle = colorbar;
colorbarHandle.Label.String = 'Normalized MUSIC power';
xlabel('Time (s)');
ylabel('Signed AoD (degrees; broadside = 0)');
title('Respiration angle-time spectrum');
bfmscan.export_figure(figureHandle, ...
    fullfile(outputDir, 'respiration_angle_time.png'));
close(figureHandle);

figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Name', 'BFMScan respiration angle-frequency spectrum');
frequencyMask = fftResult.frequency_hz <= 1;
imagesc(fftResult.frequency_hz(frequencyMask), angleGrid, ...
    10 * log10(fftResult.median_power(frequencyMask, :).' + eps));
axis xy tight;
colormap(turbo);
colorbarHandle = colorbar;
colorbarHandle.Label.String = 'Power (dB, arbitrary reference)';
xlabel('Frequency (Hz)');
ylabel('Signed AoD (degrees; broadside = 0)');
title('Windowed FFT angle-frequency spectrum');
bfmscan.export_figure(figureHandle, ...
    fullfile(outputDir, 'respiration_angle_frequency.png'));
close(figureHandle);

figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Name', 'BFMScan respiration ATR');
semilogy(angleGrid, max(fftResult.atr, eps), 'LineWidth', 1.5);
hold on;
for clusterIndex = 1:clusterCount
    members = candidateClusters{clusterIndex};
    plot(angleGrid(members), max(fftResult.atr(members), eps), ...
        'o', 'LineWidth', 1.2);
end
hold off;
grid on;
xlabel('Signed AoD (degrees; broadside = 0)');
ylabel('Respiration target-to-noise ratio (ATR)');
title(sprintf('FFT motion relevance in %.2f-%.2f Hz', ...
    options.RespirationBandHz(1), options.RespirationBandHz(2)));
bfmscan.export_figure(figureHandle, ...
    fullfile(outputDir, 'respiration_atr.png'));
close(figureHandle);

figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Name', 'BFMScan reconstructed respiration');
plot(fftResult.time_seconds, clusterSignals, 'LineWidth', 1.2);
grid on;
xlabel('Time (s)');
ylabel('Normalized PCA amplitude');
legend(compose('cluster %.1f deg', centroids), 'Location', 'best');
title('PCA-aggregated respiration signals');
bfmscan.export_figure(figureHandle, ...
    fullfile(outputDir, 'respiration_reconstructed_signals.png'));
close(figureHandle);
end

clusterId = (1:clusterCount).';
atrScore = candidateScores(:);
summary = table(clusterId, centroids, minimumAngle, maximumAngle, ...
    selectedBinCount, atrScore, dominantFrequencyHz, respirationRateBpm, ...
    waveformCosineSimilarity, ...
    'VariableNames', {'cluster_id', 'centroid_degrees', ...
    'minimum_angle_degrees', 'maximum_angle_degrees', ...
    'selected_angle_bins', 'atr_score', 'dominant_frequency_hz', ...
    'respiration_rate_bpm', 'waveform_cosine_similarity'});
writetable(summary, fullfile(outputDir, 'respiration_summary.csv'));

results = struct();
results.application = "respiration monitoring";
results.data = dataMetadata;
results.music = musicMetadata;
results.fft = fftResult;
results.mean_spatial_spectrum = meanSpatialSpectrum;
results.spatial_mask = spatialMask;
results.motion_mask = motionMask;
results.cluster_angle_indices = candidateClusters;
results.cluster_signals = clusterSignals;
results.summary = summary;
results.ground_truth_rate_bpm = groundTruthRateBpm;
results.ground_truth_offset_seconds = options.GroundTruthOffsetSeconds;
results.ground_truth_comparison = comparison;
results.ground_truth_display_polarity = comparisonPolarity;
save(fullfile(outputDir, 'respiration_results.mat'), 'results', '-v7.3');

fprintf(['Respiration: %d/%d valid packets, native median rate %.2f Hz, ' ...
    '%d selected cluster(s).\n'], sum(validPackets), numel(validPackets), ...
    dataMetadata.median_packet_rate_hz, clusterCount);
if isfinite(groundTruthRateBpm)
    fprintf('NeuLog whole-trace dominant respiration rate: %.2f bpm.\n', ...
        groundTruthRateBpm);
end
disp(summary);
end


function visibility = local_visibility(isVisible)
if isVisible
    visibility = 'on';
else
    visibility = 'off';
end
end
