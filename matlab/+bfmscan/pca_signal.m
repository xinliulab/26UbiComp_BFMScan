function signal = pca_signal(angleSignals)
%PCA_SIGNAL Aggregate angle-level signals with toolbox-free PCA via SVD.

if isempty(angleSignals)
    error('BFMScan:EmptyPcaInput', 'PCA requires at least one angle signal.');
end
centered = angleSignals - mean(angleSignals, 1);
scale = std(centered, 0, 1);
scale(scale < eps) = 1;
standardized = centered ./ scale;

if size(standardized, 2) == 1
    signal = standardized(:, 1);
else
    [leftVectors, singularValues, ~] = svd(standardized, 'econ');
    signal = leftVectors(:, 1) * singularValues(1, 1);
end

reference = mean(centered, 2);
if dot(signal, reference) < 0
    signal = -signal;
end
signal = signal - mean(signal);
signal = signal / max(std(signal), eps);
end
