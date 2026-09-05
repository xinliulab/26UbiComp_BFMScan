function varargout = run_all(outputRoot, varargin)
%RUN_ALL Compute and export the three main system-evaluation figures.
%
% From the repository root:
%   matlab -batch "run_all"
% Prints application/input/code/output paths and opens three image windows.
% On Windows, batch viewers remain open after MATLAB exits.

repoRoot = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(outputRoot)
    outputRoot = fullfile(repoRoot, 'results', 'system');
end
parser = inputParser;
parser.addParameter('ShowFigures', true, @islogical);
parser.addParameter('Verbose', false, @islogical);
parser.parse(varargin{:});
options = parser.Results;
if ~isfolder(outputRoot), mkdir(outputRoot); end
[~, outputInfo] = fileattrib(outputRoot);
outputRoot = outputInfo.Name;
addpath(repoRoot);
addpath(fullfile(repoRoot, 'matlab'));

results.figures = {fullfile(outputRoot, 'tracking_angle_time.png'), ...
    fullfile(outputRoot, 'side_detection.png'), ...
    fullfile(outputRoot, 'respiration_gt_estimate.png')};
figureNames = {'1. Device-motion MUSIC spectrum', '2. Left/right human-side detection', ...
    '3. Breathing estimate and ground truth'};
rawTracking = fullfile(repoRoot, 'experiment', 'wireshark_data', '8_27', 'ap8_27_move.txt');
rawBreathing = fullfile(repoRoot, 'experiment', 'wireshark_data', '8_7', 'bm8_7_br.txt');
belt = fullfile(repoRoot, 'experiment', 'wireshark_data', '8_7', 'bfm8_7_br.csv');

local_report(figureNames{1}, {['Raw packet export: ', rawTracking], ...
    ['Parsed BFM input: ', fullfile(repoRoot, 'experiment', 'v_data', 'ap8_27_move')]}, ...
    fullfile(repoRoot, 'bfmscan_app1_aod_tracking.m'), results.figures{1});
runLog = evalc('results.tracking = bfmscan_app1_aod_tracking([], outputRoot);');
if options.Verbose, fprintf('%s', runLog); end

local_report(figureNames{2}, { ...
    ['Measured BFM input (left): ', fullfile(repoRoot, 'experiment', 'v_data', 'left')], ...
    ['Measured BFM input (right): ', fullfile(repoRoot, 'experiment', 'v_data', 'right')], ...
    'Raw packet exports: not included for these two recordings'}, ...
    fullfile(repoRoot, 'bfmscan_side_detection.m'), results.figures{2});
runLog = evalc(['results.interaction = bfmscan_side_detection([], outputRoot, ' ...
    '''ExportDiagnostics'', false, ''ReportWarnings'', options.Verbose);']);
if options.Verbose, fprintf('%s', runLog); end

local_report(figureNames{3}, {['Raw packet export: ', rawBreathing], ...
    ['Parsed BFM input: ', fullfile(repoRoot, 'experiment', 'v_data', 'BFM_data8_7_br')], ...
    ['Ground truth: ', belt]}, ...
    fullfile(repoRoot, 'bfmscan_breathing_detection.m'), results.figures{3});
runLog = evalc(['results.respiration = bfmscan_breathing_detection([], [], outputRoot, ' ...
    '''ExportDiagnostics'', false);']);
if options.Verbose, fprintf('%s', runLog); end

for index = 1:numel(results.figures)
    if ~isfile(results.figures{index})
        error('BFMScan:MissingFigure', 'Expected figure missing: %s', results.figures{index});
    end
end
if options.ShowFigures
    results.viewers = bfmscan.show_figures(results.figures, figureNames);
    disp('Completed. Three figure windows opened.');
else
    disp('Completed. Three figures saved.');
end
if nargout > 0, varargout{1} = results; end
end


function local_report(name, inputs, codePath, figurePath)
disp(' ');
disp(name);
for index = 1:numel(inputs), disp(['  ', inputs{index}]); end
disp(['  System code: ', codePath]);
disp(['  Output PNG: ', figurePath]);
disp(['  Output data: ', fileparts(figurePath)]);
end
