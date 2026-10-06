function [packetInfos, timestamps, macAddresses, metadata] = load_bfm_folder(folderPath, varargin)
%LOAD_BFM_FOLDER Load, validate, sort, and concatenate chunked BFM MAT files.

parser = inputParser;
parser.addRequired('folderPath', @(x) ischar(x) || isstring(x));
parser.addParameter('MacAddress', "", @(x) ischar(x) || isstring(x));
parser.parse(folderPath, varargin{:});

folderPath = char(parser.Results.folderPath);
requestedMac = lower(string(parser.Results.MacAddress));
if ~isfolder(folderPath)
    error('BFMScan:MissingDataFolder', 'Data folder does not exist: %s', folderPath);
end

files = dir(fullfile(folderPath, 'packets_*.mat'));
if isempty(files)
    files = dir(fullfile(folderPath, '*.mat'));
end
if isempty(files)
    error('BFMScan:NoMatFiles', 'No MAT files found in: %s', folderPath);
end

sortKeys = inf(numel(files), 1);
for index = 1:numel(files)
    token = regexp(files(index).name, 'packets_([0-9.]+)\.mat$', 'tokens', 'once');
    if ~isempty(token)
        sortKeys(index) = str2double(token{1});
    end
end
[~, order] = sortrows([sortKeys, (1:numel(files)).']);
files = files(order);

packetBlocks = cell(numel(files), 1);
timestampBlocks = cell(numel(files), 1);
macBlocks = cell(numel(files), 1);
streamCounts = zeros(numel(files), 1);

for index = 1:numel(files)
    filePath = fullfile(files(index).folder, files(index).name);
    loaded = load(filePath);
    required = {'packet_infos', 'packet_timestamps', 'ether_srcs'};
    for requiredIndex = 1:numel(required)
        if ~isfield(loaded, required{requiredIndex})
            error('BFMScan:InvalidMatSchema', ...
                '%s is missing variable "%s".', filePath, required{requiredIndex});
        end
    end

    timestampBlock = local_numeric_timestamps(loaded.packet_timestamps);
    macBlock = local_mac_strings(loaded.ether_srcs);
    packetBlock = loaded.packet_infos;

    packetCount = numel(timestampBlock);
    if size(packetBlock, 1) ~= packetCount
        error('BFMScan:PacketCountMismatch', ...
            '%s contains %d timestamps but packet_infos has first dimension %d.', ...
            filePath, packetCount, size(packetBlock, 1));
    end
    if numel(macBlock) ~= packetCount
        error('BFMScan:MacCountMismatch', ...
            '%s contains %d timestamps but %d source MAC addresses.', ...
            filePath, packetCount, numel(macBlock));
    end
    if size(packetBlock, 3) < 2
        error('BFMScan:InvalidAntennaDimension', ...
            '%s has an invalid transmit-antenna dimension.', filePath);
    end

    streamCount = size(packetBlock, 4);
    packetBlock = reshape(packetBlock, size(packetBlock, 1), ...
        size(packetBlock, 2), size(packetBlock, 3), streamCount);

    packetBlocks{index} = packetBlock;
    timestampBlocks{index} = timestampBlock(:);
    macBlocks{index} = macBlock(:);
    streamCounts(index) = streamCount;
end

if numel(unique(streamCounts)) ~= 1
    error('BFMScan:MixedStreamCounts', ...
        'Folder %s mixes spatial-stream counts: %s', ...
        folderPath, mat2str(unique(streamCounts).'));
end

packetInfos = cat(1, packetBlocks{:});
timestamps = cat(1, timestampBlocks{:});
macAddresses = cat(1, macBlocks{:});

finiteTime = isfinite(timestamps);
if ~all(finiteTime)
    warning('BFMScan:NonfiniteTimestamps', ...
        'Dropping %d packets with invalid timestamps.', sum(~finiteTime));
    packetInfos = packetInfos(finiteTime, :, :, :);
    timestamps = timestamps(finiteTime);
    macAddresses = macAddresses(finiteTime);
end

if strlength(requestedMac) == 0
    uniqueMacs = unique(macAddresses);
    counts = zeros(numel(uniqueMacs), 1);
    for index = 1:numel(uniqueMacs)
        counts(index) = sum(macAddresses == uniqueMacs(index));
    end
    [~, dominantIndex] = max(counts);
    selectedMac = uniqueMacs(dominantIndex);
else
    selectedMac = requestedMac;
end

selected = macAddresses == selectedMac;
if ~any(selected)
    error('BFMScan:MacNotFound', ...
        'Requested source MAC %s does not occur in %s.', selectedMac, folderPath);
end
packetInfos = packetInfos(selected, :, :, :);
timestamps = timestamps(selected);
macAddresses = macAddresses(selected);

[timestamps, order] = sort(timestamps, 'ascend');
packetInfos = packetInfos(order, :, :, :);
macAddresses = macAddresses(order);

metadata = struct();
metadata.folder = string(folderPath);
metadata.file_count = numel(files);
metadata.packet_count = numel(timestamps);
metadata.selected_mac = selectedMac;
metadata.subcarrier_count = size(packetInfos, 2);
metadata.transmit_antenna_count = size(packetInfos, 3);
metadata.spatial_stream_count = size(packetInfos, 4);
if numel(timestamps) > 1
    positiveDt = diff(timestamps);
    positiveDt = positiveDt(positiveDt > 0);
    metadata.duration_seconds = timestamps(end) - timestamps(1);
    metadata.median_packet_rate_hz = 1 / median(positiveDt);
    metadata.maximum_gap_seconds = max(positiveDt);
else
    metadata.duration_seconds = 0;
    metadata.median_packet_rate_hz = NaN;
    metadata.maximum_gap_seconds = NaN;
end
end


function timestamps = local_numeric_timestamps(raw)
if isnumeric(raw)
    timestamps = double(raw(:));
elseif ischar(raw)
    timestamps = str2double(string(cellstr(raw)));
elseif isstring(raw)
    timestamps = str2double(raw(:));
elseif iscell(raw)
    timestamps = str2double(string(raw(:)));
else
    error('BFMScan:InvalidTimestamps', ...
        'Unsupported packet_timestamps type: %s', class(raw));
end
timestamps = timestamps(:);
end


function macAddresses = local_mac_strings(raw)
if ischar(raw)
    macAddresses = string(cellstr(raw));
elseif isstring(raw)
    macAddresses = raw(:);
elseif iscell(raw)
    macAddresses = string(raw(:));
else
    error('BFMScan:InvalidMacAddresses', ...
        'Unsupported ether_srcs type: %s', class(raw));
end
macAddresses = lower(strtrim(macAddresses(:)));
end
