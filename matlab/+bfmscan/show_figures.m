function viewers = show_figures(paths, names)
%SHOW_FIGURES Open separate viewers that survive Windows MATLAB batch exit.

viewers = struct('kind', '', 'process_ids', []);
if usejava('desktop')
    for index = 1:numel(paths)
        figure('Name', names{index}, 'NumberTitle', 'off', 'Color', 'w', ...
            'WindowStyle', 'normal', 'Position', [80+40*index, 80+40*index, 1100, 650]);
        image(imread(paths{index})); axis image off;
    end
    drawnow;
    viewers.kind = 'MATLAB figures';
    return;
end
if ~ispc
    error('BFMScan:BatchViewerUnavailable', ...
        ['Persistent batch pop-outs require Windows. Use MATLAB Desktop, ' ...
        'or run_all([], ''ShowFigures'', false) to save figures only.']);
end

executable = fullfile(getenv('SystemRoot'), 'System32', ...
    'WindowsPowerShell', 'v1.0', 'powershell.exe');
if ~isfile(executable)
    error('BFMScan:MissingViewerRuntime', 'Windows PowerShell was not found: %s', executable);
end
viewers.kind = 'Windows image windows';
for index = 1:numel(paths)
    % WPF decodes the PNG before showing it, leaving no file lock behind.
    % Each process owns one modal window and exits when that window is closed.
    script = strjoin({ ...
        '$ErrorActionPreference=''Stop''', ...
        'Add-Type -AssemblyName PresentationFramework', ...
        '$window=New-Object System.Windows.Window', ...
        ['$window.Title=', local_quote(['BFMScan ', names{index}])], ...
        '$window.Width=1100; $window.Height=650', ...
        '$window.WindowStartupLocation=''Manual''', ...
        sprintf('$window.Left=%d; $window.Top=%d', 60+50*index, 60+50*index), ...
        '$window.Background=''White''', ...
        '$picture=New-Object System.Windows.Controls.Image', ...
        '$picture.Stretch=''Uniform''', ...
        '$bitmap=New-Object System.Windows.Media.Imaging.BitmapImage', ...
        '$bitmap.BeginInit(); $bitmap.CacheOption=''OnLoad''', ...
        ['$bitmap.UriSource=New-Object System.Uri(', local_quote(paths{index}), ')'], ...
        '$bitmap.EndInit(); $picture.Source=$bitmap', ...
        '$window.Content=$picture', ...
        '$window.Add_ContentRendered({$this.Activate() | Out-Null})', ...
        '$window.ShowDialog() | Out-Null'}, newline);
    encoded = matlab.net.base64encode(unicode2native(script, 'UTF-16LE'));
    startInfo = System.Diagnostics.ProcessStartInfo;
    startInfo.FileName = executable;
    startInfo.Arguments = ['-NoProfile -STA -EncodedCommand ', encoded];
    startInfo.UseShellExecute = true;
    % Hide the helper console, not its image window.
    startInfo.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;
    process = System.Diagnostics.Process.Start(startInfo);
    viewers.process_ids(end+1) = double(process.Id); %#ok<AGROW>
    ready = false;
    started = tic;
    while toc(started) < 15
        process.Refresh();
        if process.HasExited, break; end
        if startsWith(char(process.MainWindowTitle), 'BFMScan ')
            ready = true;
            break;
        end
        pause(0.1);
    end
    if ~ready
        error('BFMScan:ViewerFailed', 'The image viewer did not open: %s', paths{index});
    end
    process.Dispose();
end
end


function quoted = local_quote(value)
quoted = ['''', strrep(char(value), '''', ''''''), ''''];
end
