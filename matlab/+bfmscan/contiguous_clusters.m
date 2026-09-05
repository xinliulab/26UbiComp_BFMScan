function clusters = contiguous_clusters(mask, minimumBins)
%CONTIGUOUS_CLUSTERS Return contiguous true-index groups from a logical mask.

if nargin < 2
    minimumBins = 1;
end
mask = logical(mask(:).');
edges = diff([false, mask, false]);
starts = find(edges == 1);
stops = find(edges == -1) - 1;
clusters = {};
for index = 1:numel(starts)
    members = starts(index):stops(index);
    if numel(members) >= minimumBins
        clusters{end + 1} = members; %#ok<AGROW>
    end
end
end
