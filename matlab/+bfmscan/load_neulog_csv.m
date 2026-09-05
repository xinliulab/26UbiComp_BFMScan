function data = load_neulog_csv(filePath)
%LOAD_NEULOG_CSV Load the time, pulse, and respiration columns in NeuLog CSV.

if ~isfile(filePath)
    error('BFMScan:MissingGroundTruth', ...
        'NeuLog ground-truth file does not exist: %s', filePath);
end
lines = readlines(filePath);
timeSeconds = [];
pulse = [];
respiration = [];

for index = 8:numel(lines)
    fields = split(lines(index), ',');
    if numel(fields) ~= 3
        continue;
    end
    timeText = erase(strtrim(fields(1)), ["'", '"']);
    pieces = split(timeText, ':');
    if numel(pieces) ~= 3
        continue;
    end
    hour = str2double(pieces(1));
    minute = str2double(pieces(2));
    second = str2double(pieces(3));
    pulseValue = str2double(fields(2));
    respirationValue = str2double(fields(3));
    if any(~isfinite([hour, minute, second, pulseValue, respirationValue]))
        continue;
    end
    timeSeconds(end + 1, 1) = 3600 * hour + 60 * minute + second; %#ok<AGROW>
    pulse(end + 1, 1) = pulseValue; %#ok<AGROW>
    respiration(end + 1, 1) = respirationValue; %#ok<AGROW>
end

if isempty(timeSeconds)
    error('BFMScan:InvalidGroundTruth', ...
        'No numeric NeuLog samples were found in %s.', filePath);
end
timeSeconds = timeSeconds - timeSeconds(1);
data = table(timeSeconds, pulse, respiration, ...
    'VariableNames', {'time_seconds', 'pulse', 'respiration'});
end
