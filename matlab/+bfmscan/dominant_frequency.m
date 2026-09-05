function [frequencyHz, frequency, power] = dominant_frequency(signal, samplingRate, bandHz)
%DOMINANT_FREQUENCY Estimate the largest Hann-windowed FFT peak in a band.

signal = signal(:);
signal = detrend(signal, 0);
sampleCount = numel(signal);
if sampleCount < 3
    frequencyHz = NaN;
    frequency = [];
    power = [];
    return;
end
window = 0.5 - 0.5 * cos(2 * pi * (0:sampleCount-1).' ...
    / max(sampleCount - 1, 1));
fftLength = 2 ^ nextpow2(sampleCount);
transformed = fft(signal .* window, fftLength);
frequency = (0:floor(fftLength / 2)).' * samplingRate / fftLength;
power = abs(transformed(1:numel(frequency))) .^ 2;
inBand = frequency >= bandHz(1) & frequency <= bandHz(2);
if ~any(inBand)
    frequencyHz = NaN;
    return;
end
bandFrequency = frequency(inBand);
bandPower = power(inBand);
[~, peakIndex] = max(bandPower);
frequencyHz = bandFrequency(peakIndex);
end
