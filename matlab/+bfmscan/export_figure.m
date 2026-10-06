function export_figure(figureHandle, outputPath)
%EXPORT_FIGURE Export a reproducible 160-DPI PNG, creating parents as needed.

parent = fileparts(outputPath);
if ~isempty(parent) && ~isfolder(parent)
    mkdir(parent);
end
exportgraphics(figureHandle, outputPath, 'Resolution', 160);
end
