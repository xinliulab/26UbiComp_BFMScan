function results = bfmscan_app1_aod_tracking(dataFolder, outputDir, varargin)
%BFMSCAN_APP1_AOD_TRACKING Reproduce the device-based angular tracking demo.
%
% Example:
%   results = bfmscan_app1_aod_tracking();

repoRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(repoRoot, 'matlab'));
if nargin < 1 || isempty(dataFolder)
    dataFolder = fullfile(repoRoot, 'experiment', 'v_data', 'ap8_27_move');
end
if nargin < 2 || isempty(outputDir)
    outputDir = fullfile(repoRoot, 'results', 'tracking');
end

parser = inputParser;
parser.addParameter('CarrierFrequencyHz', 5.765e9, @isnumeric);
parser.addParameter('StreamsToUse', 2, @isnumeric);
parser.addParameter('SmoothingWindowPackets', 5, @isnumeric);
parser.addParameter('FigureVisible', false, @(x) islogical(x) || isnumeric(x));
parser.addParameter('MovementAnglesDegrees', [], @(x) isempty(x) || ...
    (isnumeric(x) && numel(x) == 2 && all(isfinite(x))));
parser.parse(varargin{:});
options = parser.Results;
bundledData = fullfile(repoRoot, 'experiment', 'v_data', 'ap8_27_move');
if isempty(options.MovementAnglesDegrees) && strcmp(char(dataFolder), bundledData)
    % Author-provided experiment endpoints; these do not modify the spectrum.
    options.MovementAnglesDegrees = [30, -45];
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

peakAod = NaN(numel(timestamps), 1);
[~, peakIndices] = max(angleSpectrum(validPackets, :), [], 2);
peakAod(validPackets) = angleGrid(peakIndices);
smoothedAod = peakAod;
if sum(validPackets) >= 3
    smoothedAod(validPackets) = smoothdata(peakAod(validPackets), ...
        'movmedian', options.SmoothingWindowPackets);
end
relativeTime = timestamps - timestamps(1);
validIndices = find(validPackets);
firstIndex = validIndices(1);
lastIndex = validIndices(end);
startAngle = peakAod(firstIndex);
endAngle = peakAod(lastIndex);

visibility = local_visibility(options.FigureVisible);
figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Name', 'BFMScan device-motion MUSIC spectrum', 'Position', [100 100 1100 550]);
% Use the actual irregular timestamps as surface vertices. Display colors are
% interpolated between measurements; no trajectory is drawn over the spectrum.
surface(relativeTime(validPackets), angleGrid, ...
    zeros(numel(angleGrid), sum(validPackets)), angleSpectrum(validPackets, :).', ...
    'EdgeColor', 'none', 'FaceColor', 'interp');
view(2); axis xy tight;
colormap(turbo);
colorbarHandle = colorbar;
colorbarHandle.Label.String = 'Normalized MUSIC power';
xlabel('Time (s)');
ylabel('Signed AoD (degrees; broadside = 0)');
if isempty(options.MovementAnglesDegrees)
    endpointText = sprintf('Estimated peak angle: start %+.0f deg, end %+.0f deg', ...
        startAngle, endAngle);
else
    endpointText = sprintf('Device movement: %+.0f deg to %+.0f deg', ...
        options.MovementAnglesDegrees(1), options.MovementAnglesDegrees(2));
end
title({'Device motion: angle-time MUSIC spectrum', endpointText});
bfmscan.export_figure(figureHandle, ...
    fullfile(outputDir, 'tracking_angle_time.png'));
close(figureHandle);

trackingTable = table(timestamps, relativeTime, validPackets, ...
    peakAod, smoothedAod, ...
    'VariableNames', {'timestamp_seconds', 'relative_time_seconds', ...
    'valid_packet', 'peak_aod_degrees', 'smoothed_aod_degrees'});
writetable(trackingTable, fullfile(outputDir, 'tracking_trajectory.csv'));

results = struct();
results.application = "device-based angular tracking";
results.data = dataMetadata;
results.music = musicMetadata;
results.timestamps = timestamps;
results.relative_time_seconds = relativeTime;
results.angle_spectrum = angleSpectrum;
results.valid_packets = validPackets;
results.peak_aod_degrees = peakAod;
results.smoothed_aod_degrees = smoothedAod;
results.start_angle_degrees = startAngle;
results.end_angle_degrees = endAngle;
results.endpoint_method = "dominant MUSIC peaks of the first and last valid packets";
results.movement_angle_labels_degrees = options.MovementAnglesDegrees;
save(fullfile(outputDir, 'tracking_results.mat'), 'results', '-v7.3');

fprintf(['Tracking: %d/%d valid packets, %.2f s, median packet rate ' ...
    '%.2f Hz, source MAC %s.\n'], ...
    sum(validPackets), numel(validPackets), dataMetadata.duration_seconds, ...
    dataMetadata.median_packet_rate_hz, dataMetadata.selected_mac);
end


function visibility = local_visibility(isVisible)
if isVisible
    visibility = 'on';
else
    visibility = 'off';
end
end
