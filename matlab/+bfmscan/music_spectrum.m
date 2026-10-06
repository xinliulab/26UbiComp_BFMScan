function [spectrum, validPackets, metadata] = music_spectrum(packetInfos, varargin)
%MUSIC_SPECTRUM Recover per-packet signed AoD spectra from compressed BFM.
%
% The implementation follows Equations (7)-(11) in the BFMScan paper:
% projection matrices are formed per subcarrier, averaged within a packet,
% and used to recover the transmit-side noise subspace.  A coarse 3-degree
% scan is linearly interpolated onto a 1-degree grid by default.

parser = inputParser;
parser.addRequired('packetInfos', @isnumeric);
parser.addParameter('CarrierFrequencyHz', 5.765e9, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.addParameter('StreamsToUse', [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && x >= 1));
parser.addParameter('CoarseStepDegrees', 3, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.addParameter('FineStepDegrees', 1, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.parse(packetInfos, varargin{:});
options = parser.Results;

packetCount = size(packetInfos, 1);
subcarrierCount = size(packetInfos, 2);
transmitAntennas = size(packetInfos, 3);
availableStreams = size(packetInfos, 4);
if isempty(options.StreamsToUse)
    streamsToUse = availableStreams;
else
    streamsToUse = min(availableStreams, round(options.StreamsToUse));
end
streamsToUse = min(streamsToUse, transmitAntennas - 1);
if streamsToUse < 1
    error('BFMScan:NoNoiseSubspace', ...
        'At least two transmit antennas and one signal stream are required.');
end

speedOfLight = 299792458;
wavelength = speedOfLight / options.CarrierFrequencyHz;
antennaSpacing = wavelength / 2;
coarseAngles = -90:options.CoarseStepDegrees:90;
fineAngles = -90:options.FineStepDegrees:90;
antennaIndices = (0:transmitAntennas-1).';
steering = exp(-1j * 2 * pi * antennaSpacing / wavelength ...
    * antennaIndices * sind(coarseAngles));

spectrum = zeros(packetCount, numel(fineAngles));
validPackets = false(packetCount, 1);
validSubcarrierCounts = zeros(packetCount, 1);
semiunitaryErrors = [];

for packetIndex = 1:packetCount
    signalProjection = zeros(transmitAntennas, transmitAntennas);
    validSubcarriers = 0;

    for subcarrierIndex = 1:subcarrierCount
        value = reshape(packetInfos(packetIndex, subcarrierIndex, ...
            :, 1:streamsToUse), transmitAntennas, streamsToUse);
        if any(~isfinite(value(:)))
            continue;
        end
        gram = value' * value;
        if rcond(gram) < 1e-10
            continue;
        end

        % This is V(V^H V)^-1 V^H.  Keeping the Gram correction makes the
        % projector robust to finite-bit feedback and parser rounding.
        signalProjection = signalProjection + value * (gram \ value');
        validSubcarriers = validSubcarriers + 1;
        semiunitaryErrors(end + 1, 1) = norm( ...
            gram - eye(streamsToUse), 'fro'); %#ok<AGROW>
    end

    if validSubcarriers == 0
        continue;
    end
    signalProjection = signalProjection / validSubcarriers;
    signalProjection = (signalProjection + signalProjection') / 2;

    [eigenvectors, eigenvalues] = eig(signalProjection, 'vector');
    [~, order] = sort(real(eigenvalues), 'ascend');
    noiseDimension = transmitAntennas - streamsToUse;
    noiseSubspace = eigenvectors(:, order(1:noiseDimension));
    noiseProjection = noiseSubspace * noiseSubspace';

    denominator = real(sum(conj(steering) .* ...
        (noiseProjection * steering), 1));
    coarseSpectrum = 1 ./ max(denominator, 1e-12);
    coarseSpectrum = coarseSpectrum / max(coarseSpectrum);
    fineSpectrum = interp1(coarseAngles, coarseSpectrum, ...
        fineAngles, 'linear');

    spectrum(packetIndex, :) = max(real(fineSpectrum), 0);
    validPackets(packetIndex) = true;
    validSubcarrierCounts(packetIndex) = validSubcarriers;
end

metadata = struct();
metadata.angle_grid_degrees = fineAngles;
metadata.coarse_angle_grid_degrees = coarseAngles;
metadata.carrier_frequency_hz = options.CarrierFrequencyHz;
metadata.antenna_spacing_m = antennaSpacing;
metadata.streams_used = streamsToUse;
metadata.valid_packet_count = sum(validPackets);
metadata.valid_subcarriers_per_packet = validSubcarrierCounts;
if isempty(semiunitaryErrors)
    metadata.median_semiunitary_error = NaN;
    metadata.maximum_semiunitary_error = NaN;
else
    metadata.median_semiunitary_error = median(semiunitaryErrors);
    metadata.maximum_semiunitary_error = max(semiunitaryErrors);
end
end
