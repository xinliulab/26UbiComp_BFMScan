function result = angle_time_fft(spectrum, validPackets, timestamps, angleGrid, varargin)
%ANGLE_TIME_FFT Uniform resampling, windowed FFT, and per-angle ATR.
%
% This implements the paper's temporal pipeline: irregular packet samples
% are interpolated to 20 Hz, analyzed in 30-second windows, and scored using
% the target-motion-to-noise ratio from Equation (18).

parser = inputParser;
parser.addRequired('spectrum', @isnumeric);
parser.addRequired('validPackets', @(x) islogical(x) || isnumeric(x));
parser.addRequired('timestamps', @isnumeric);
parser.addRequired('angleGrid', @isnumeric);
parser.addParameter('SamplingRateHz', 20, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.addParameter('WindowSeconds', 30, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.addParameter('WindowOverlap', 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
parser.addParameter('TargetBandHz', [0.15, 0.4], ...
    @(x) isnumeric(x) && numel(x) == 2 && x(1) >= 0 && x(2) > x(1));
parser.parse(spectrum, validPackets, timestamps, angleGrid, varargin{:});
options = parser.Results;

timestamps = timestamps(:);
validPackets = logical(validPackets(:));
rowFinite = all(isfinite(spectrum), 2);
keep = validPackets & isfinite(timestamps) & rowFinite;
if sum(keep) < 3
    error('BFMScan:InsufficientTemporalSamples', ...
        'At least three valid time samples are required.');
end

time = timestamps(keep);
values = spectrum(keep, :);
[time, order] = sort(time, 'ascend');
values = values(order, :);

[uniqueTime, ~, groups] = unique(time);
if numel(uniqueTime) < numel(time)
    merged = zeros(numel(uniqueTime), size(values, 2));
    for angleIndex = 1:size(values, 2)
        merged(:, angleIndex) = accumarray(groups, values(:, angleIndex), ...
            [], @mean);
    end
    time = uniqueTime;
    values = merged;
end

positiveDt = diff(time);
positiveDt = positiveDt(positiveDt > 0);
nativeRate = 1 / median(positiveDt);
if nativeRate < 2 * options.TargetBandHz(2)
    warning('BFMScan:TemporalUndersampling', ...
        ['Native median packet rate %.3f Hz is below twice the target-band ' ...
        'upper edge %.3f Hz. Interpolation cannot recover missing dynamics.'], ...
        nativeRate, options.TargetBandHz(2));
end

samplingRate = options.SamplingRateHz;
startTime = ceil(time(1) * samplingRate) / samplingRate;
endTime = floor(time(end) * samplingRate) / samplingRate;
uniformTime = (startTime:1/samplingRate:endTime).';
windowSamples = round(options.WindowSeconds * samplingRate);
if numel(uniformTime) < windowSamples
    error('BFMScan:TraceTooShortForFft', ...
        'Trace duration %.2f s is shorter than the %.2f s FFT window.', ...
        time(end) - time(1), options.WindowSeconds);
end

uniformValues = interp1(time, values, uniformTime, 'linear');
uniformValues = detrend(uniformValues, 0);

hopSamples = max(1, round(windowSamples * (1 - options.WindowOverlap)));
windowStarts = 1:hopSamples:(numel(uniformTime) - windowSamples + 1);
lastStart = numel(uniformTime) - windowSamples + 1;
if windowStarts(end) ~= lastStart
    windowStarts(end + 1) = lastStart;
end

fftLength = 2 ^ nextpow2(windowSamples);
frequency = (0:floor(fftLength / 2)).' * samplingRate / fftLength;
targetMask = frequency >= options.TargetBandHz(1) ...
    & frequency <= options.TargetBandHz(2);
noiseMask = frequency > 0 & ~targetMask;
window = 0.5 - 0.5 * cos(2 * pi * (0:windowSamples-1).' ...
    / max(windowSamples - 1, 1));

powerByWindow = zeros(numel(frequency), size(values, 2), numel(windowStarts));
atrByWindow = zeros(numel(windowStarts), size(values, 2));
for windowIndex = 1:numel(windowStarts)
    indices = windowStarts(windowIndex) ...
        + (0:windowSamples-1);
    segment = detrend(uniformValues(indices, :), 0);
    transformed = fft(segment .* window, fftLength, 1);
    power = abs(transformed(1:numel(frequency), :)) .^ 2;
    powerByWindow(:, :, windowIndex) = power;
    targetEnergy = sum(power(targetMask, :), 1);
    noiseEnergy = sum(power(noiseMask, :), 1);
    atrByWindow(windowIndex, :) = targetEnergy ./ max(noiseEnergy, eps);
end

medianPower = median(powerByWindow, 3);
atr = median(atrByWindow, 1);
dominantFrequency = NaN(1, size(values, 2));
bandFrequencies = frequency(targetMask);
for angleIndex = 1:size(values, 2)
    [~, peakIndex] = max(medianPower(targetMask, angleIndex));
    if ~isempty(peakIndex)
        dominantFrequency(angleIndex) = bandFrequencies(peakIndex);
    end
end

result = struct();
result.time_seconds = uniformTime - uniformTime(1);
result.absolute_time_seconds = uniformTime;
result.signals = uniformValues;
result.frequency_hz = frequency;
result.median_power = medianPower;
result.atr = atr;
result.atr_by_window = atrByWindow;
result.dominant_frequency_hz = dominantFrequency;
result.angle_grid_degrees = angleGrid(:).';
result.window_start_seconds = uniformTime(windowStarts) - uniformTime(1);
result.sampling_rate_hz = samplingRate;
result.native_median_packet_rate_hz = nativeRate;
result.maximum_native_gap_seconds = max(positiveDt);
result.window_seconds = options.WindowSeconds;
result.target_band_hz = options.TargetBandHz;
end
