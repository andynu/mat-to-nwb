function nwbFilePath = convertMatToNwb(matFilePath, sessionDescription, experimenterName)
% convertMatToNwb - Convert a MATLAB data file to NWB format
%
% Inputs:
%   matFilePath - Path to the MATLAB .mat file to convert
%   sessionDescription - Description of the session (optional)
%   experimenterName - Name of the experimenter (optional)
%
% Output:
%   nwbFilePath - Path to the generated NWB file
%
% Example:
%   nwbFile = convertMatToNwb('./MATLABFiles/mouse1_VLS_42_control.mat', 'VLS session 42', 'Your name');

% Add matnwb to path relative to this script's location
[scriptPath, ~, ~] = fileparts(mfilename('fullpath')); 
addpath(fullfile(scriptPath, 'matnwb'));

% Set default values for optional parameters
if nargin < 2
    sessionDescription = 'Converted MATLAB session';
end
if nargin < 3
    experimenterName = 'Unknown';
end

% Parse filename components
[animal, signal, session, tag] = parseFileName(matFilePath);

% Load MATLAB data
matData = load(matFilePath);

% Find the earliest timestamp in the data
earliestTime = inf;
fieldNames = fieldnames(matData);
allFieldNames = {};

% First pass: collect all field names and find timestamps
for i = 1:length(fieldNames)
    fieldName = fieldNames{i};
    currentStruct = matData.(fieldName);
    
    % Add to our collection of field names
    allFieldNames{end+1} = fieldName;
    
    % Check for time field
    possibleTimeFields = {'times', 'time', 't', 'timestamps'};
    for j = 1:length(possibleTimeFields)
        if isfield(currentStruct, possibleTimeFields{j})
            timeData = currentStruct.(possibleTimeFields{j});
            if isnumeric(timeData) && ~isempty(timeData)
                earliestTime = min(earliestTime, min(timeData));
            end
            break;
        end
    end
    
    % Also collect any inner field names that might be used
    innerFields = fieldnames(currentStruct);
    for j = 1:length(innerFields)
        combinedName = [fieldName '_' innerFields{j}];
        allFieldNames{end+1} = combinedName;
    end
end

% Find the longest common prefix
if ~isempty(allFieldNames)
    % Start with the first field name
    commonPrefix = allFieldNames{1};
    
    % Compare with each subsequent field name
    for i = 2:length(allFieldNames)
        currentName = allFieldNames{i};
        
        % Find where the strings differ
        minLength = min(length(commonPrefix), length(currentName));
        
        if minLength == 0
            commonPrefix = '';
            break;
        end
        
        % Find the first differing character
        matchLength = 0;
        for j = 1:minLength
            if commonPrefix(j) ~= currentName(j)
                matchLength = j - 1;
                break;
            end
            matchLength = j;
        end
        
        if matchLength > 0
            commonPrefix = commonPrefix(1:matchLength);
        else
            commonPrefix = '';
            break;
        end
    end
    
    % Make sure we end at a complete word (at an underscore)
    if ~isempty(commonPrefix)
        lastUnderscore = find(commonPrefix == '_', 1, 'last');
        if ~isempty(lastUnderscore)
            commonPrefix = commonPrefix(1:lastUnderscore);
        end
    end
    
    prefixToStrip = commonPrefix;
else
    prefixToStrip = '';
end

% Create timezone-aware datetime for session start time
sessionStartTime = datetime('now', 'TimeZone', 'local');
sessionStartTime = sessionStartTime - seconds(sessionStartTime.Hour*3600 + sessionStartTime.Minute*60 + sessionStartTime.Second);
sessionStartTime = sessionStartTime + seconds(earliestTime);

% Create an NWB file with parsed metadata
nwb = NwbFile(...
    'session_description', sessionDescription,...
    'identifier', [animal '_' signal '_' session '_' tag],...
    'session_start_time', sessionStartTime,...
    'general_experimenter', experimenterName,...
    'general_subject', types.core.Subject('subject_id', animal),...
    'general_session_id', session,...
    'general_institution', 'Whitehead Institute',...
    'general_notes', sprintf('Signal Type: %s, Tag: %s', signal, tag));

% Set timestamps reference time to be the same as session start time
nwb.timestamps_reference_time = sessionStartTime;

% Examine structure of first field to understand the data
firstField = fieldNames{1};

% Get field names within the struct
innerFieldNames = fieldnames(matData.(firstField));

% Now extract data from common fields like 'times' and 'values' that are typical in MATLAB recordings
for i = 1:length(fieldNames)
    fieldName = fieldNames{i};
    currentStruct = matData.(fieldName);
    
    % Try to extract common fields used in neurophysiology data
    % Check for time/values fields with different possible names
    timeField = '';
    dataField = '';
    
    % Check for common time field names
    possibleTimeFields = {'times', 'time', 't', 'timestamps'};
    for j = 1:length(possibleTimeFields)
        if isfield(currentStruct, possibleTimeFields{j})
            timeField = possibleTimeFields{j};
            break;
        end
    end
    
    % Check for common data field names
    possibleDataFields = {'values', 'value', 'data', 'signal', 'amplitude', 'position', 'X', 'Y', 'X'};
    for j = 1:length(possibleDataFields)
        if isfield(currentStruct, possibleDataFields{j})
            dataField = possibleDataFields{j};
            break;
        end
    end
    
    % If we found both fields, create a TimeSeries
    if ~isempty(timeField) && ~isempty(dataField)
        timeData = currentStruct.(timeField);
        valueData = currentStruct.(dataField);
        
        % Ensure data is in the correct format
        if ~isnumeric(timeData) || ~isnumeric(valueData)
            warning(['Data for ' fieldName ' is not numeric. Skipping.']);
            continue;
        end
        
        % IMPORTANT: MatNWB transposes data when writing to HDF5
        % For DataPipe, we need data as row vectors (1xM) so it becomes (M,1) in HDF5
        % For direct assignment, we need data as column vectors (Mx1)
        
        % Ensure timestamps are in the correct format for NWB (row vector for DataPipe)
        if isvector(timeData)
            if size(timeData, 2) == 1  % If it's a column vector
                timeData = timeData';  % Transpose to row vector
                disp(['  Transposing timestamps for ' fieldName ' to row vector for DataPipe']);
            end
        end
        
        % For vector data, ensure it's a row vector for DataPipe
        if isvector(valueData)
            if size(valueData, 2) == 1  % If it's a column vector
                valueData = valueData';  % Transpose to row vector
                disp(['  Transposing vector data for ' fieldName ' to row vector for DataPipe']);
            end
        else
            % For multi-dimensional arrays, we need to handle differently
            % This would require more complex transformation
            disp(['  Warning: ' fieldName ' is multi-dimensional. Dimension handling may be complex.']);
        end
        
        % Create TimeSeries object
        % Check if timestamps are evenly spaced (constant sampling rate)
        if length(timeData) > 1
            % Calculate differences between timestamps
            diffs = diff(timeData);
            
            if std(diffs) < 1e-10  % Threshold for considering timestamps regular
                % Use starting_time and starting_time_rate instead of timestamps
                sampling_rate = 1/diffs(1);  % Calculate rate from time difference
                
                % For all datasets, use DataPipe with row vectors (1xM)
                compressedData = types.untyped.DataPipe(...
                    'data', valueData,...  % Should be row vector (1xM)
                    'compressionLevel', 3,...
                    'axis', 2);  % axis=2 for row vectors since time is in second dimension
                
                ts = types.core.TimeSeries(...
                    'data', compressedData,...
                    'data_unit', 'unknown',...
                    'starting_time', timeData(1),...
                    'starting_time_rate', sampling_rate,...
                    'description', fieldName);
                disp('  Using starting_time and starting_time_rate instead of timestamps (regular sampling detected)');
            else
                % Use timestamps for irregular sampling
                
                % For all datasets, use DataPipe with row vectors (1xM)
                compressedData = types.untyped.DataPipe(...
                    'data', valueData,...  % Should be row vector (1xM)
                    'compressionLevel', 3,...
                    'axis', 2);  % axis=2 for row vectors since time is in second dimension
                
                ts = types.core.TimeSeries(...
                    'data', compressedData,...
                    'data_unit', 'unknown',...
                    'timestamps', timeData,...  % Should be row vector (1xM)
                    'description', fieldName);
            end
        else
            % If only one timestamp, use it as starting_time with default rate
            
            % For all datasets, use DataPipe with row vectors (1xM)
            compressedData = types.untyped.DataPipe(...
                'data', valueData,...  % Should be row vector (1xM)
                'compressionLevel', 3,...
                'axis', 2);  % axis=2 for row vectors since time is in second dimension
            
            ts = types.core.TimeSeries(...
                'data', compressedData,...
                'data_unit', 'unknown',...
                'starting_time', timeData(1),...
                'starting_time_rate', 1.0,...
                'description', fieldName);
            disp('  Using starting_time and starting_time_rate instead of timestamps (single timestamp)');
        end
        
        % Strip the prefix and keep the event name with _times if present
        if startsWith(fieldName, prefixToStrip)
            % Remove the prefix
            stripped = fieldName(length(prefixToStrip)+1:end);
            if startsWith(stripped, '_')
                stripped = stripped(2:end);
            end
            
            % If it's an event with _times, keep that part
            if endsWith(stripped, '_times')
                strippedFieldName = stripped;
            else
                % For other fields, take just the last part
                parts = strsplit(stripped, '_');
                strippedFieldName = parts{end};
            end
        else
            strippedFieldName = fieldName;
        end
        
        nwb.acquisition.set(strippedFieldName, ts);
        disp(' ');
        disp(['FIELD: ' strippedFieldName]);
        disp(['  Data shape: ' num2str(size(valueData))]);
        disp(['  Timestamps shape: ' num2str(size(timeData))]);
        disp(['  Time field used: ' timeField]);
        disp(['  Data field used: ' dataField]);
        disp('  STATUS: Successfully added to NWB path /acquisition/' + string(strippedFieldName));
    else
        % If we didn't find standard fields, try to use the first numeric field
        innerFields = fieldnames(currentStruct);
        foundNumeric = false;
        
        for j = 1:length(innerFields)
            innerFieldName = innerFields{j};
            innerValue = currentStruct.(innerFieldName);
            
            if isnumeric(innerValue) && ~isempty(innerValue)
                % Ensure time is in the first dimension by explicitly transposing the data
                % For 1D arrays, ensure they are column vectors (time in first dimension)
                if isvector(innerValue)
                    if size(innerValue, 1) == 1  % If it's a row vector
                        innerValue = innerValue';  % Transpose to column vector
                        disp(['  Transposing vector data for ' fieldName '_' innerFieldName ' to make time the first dimension']);
                    end
                else
                    % For multi-dimensional arrays, transpose if needed
                    innerValueSize = size(innerValue);
                    % Check if data is likely in wrong orientation (another dimension is longer)
                    if length(innerValueSize) > 1 && innerValueSize(1) < max(innerValueSize)
                        % If the data is 2D, simply use transpose
                        if length(innerValueSize) == 2
                            innerValue = innerValue';
                            disp(['  Transposing 2D data for ' fieldName '_' innerFieldName ' to make time the first dimension']);
                        else
                            % For higher dimensions, use permute to move the longest dimension first
                            [~, longestDim] = max(innerValueSize);
                            permVec = 1:length(innerValueSize);
                            permVec(1) = longestDim;
                            permVec(longestDim) = 1;
                            innerValue = permute(innerValue, permVec);
                            disp(['  Permuting ' num2str(length(innerValueSize)) 'D data for ' fieldName '_' innerFieldName ' to make time the first dimension']);
                        end
                        disp(['  New data shape: ' num2str(size(innerValue))]);
                    end
                end
                
                % Found a numeric field, use it as data
                if size(innerValue, 1) > 1
                    % Data is multi-dimensional, create timestamps
                    timestamps = 0:(size(innerValue,1)-1);
                    
                    % Ensure timestamps are in the correct format for NWB (row vector for DataPipe)
                    if isvector(timestamps)
                        if size(timestamps, 2) == 1  % If it's a column vector
                            timestamps = timestamps';  % Transpose to row vector
                            disp(['  Transposing timestamps for ' fieldName '_' innerFieldName ' to row vector for DataPipe']);
                        end
                    end
                    
                    % For vector data, ensure it's a row vector for DataPipe
                    if isvector(innerValue)
                        if size(innerValue, 2) == 1  % If it's a column vector
                            innerValue = innerValue';  % Transpose to row vector
                            disp(['  Transposing vector data for ' fieldName '_' innerFieldName ' to row vector for DataPipe']);
                        end
                    else
                        % For multi-dimensional arrays, we need to handle differently
                        % This would require more complex transformation
                        disp(['  Warning: ' fieldName '_' innerFieldName ' is multi-dimensional. Dimension handling may be complex.']);
                    end
                    
                    % Create TimeSeries object
                    % Check if timestamps are evenly spaced (constant sampling rate)
                    if length(timestamps) > 1
                        diffs = diff(timestamps);
                        if std(diffs) < 1e-10  % Threshold for considering timestamps regular
                            % Use starting_time and starting_time_rate instead of timestamps
                            sampling_rate = 1/diffs(1);  % Calculate rate from time difference
                            
                            % For NWB, we need to ensure time is in the first dimension
                            % Now reintroduce compression with DataPipe, maintaining correct orientation
                            % The data is already properly oriented as a column vector
                            compressedData = types.untyped.DataPipe(...
                                'data', innerValue,...  % Already a column vector (Nx1)
                                'compressionLevel', 3,...
                                'axis', 1);  % axis=1 means time is in the first dimension
                            
                            ts = types.core.TimeSeries(...
                                'data', compressedData,...
                                'data_unit', 'unknown',...
                                'starting_time', timestamps(1),...
                                'starting_time_rate', sampling_rate,...
                                'description', [fieldName '_' innerFieldName]);
                            disp('  Using starting_time and starting_time_rate instead of timestamps (regular sampling detected)');
                        else
                            % Use timestamps for irregular sampling
                            
                            % For NWB, we need to ensure time is in the first dimension
                            % Now reintroduce compression with DataPipe, maintaining correct orientation
                            % The data is already properly oriented as a column vector
                            compressedData = types.untyped.DataPipe(...
                                'data', innerValue,...  % Already a column vector (Nx1)
                                'compressionLevel', 3,...
                                'axis', 1);  % axis=1 means time is in the first dimension
                            
                            ts = types.core.TimeSeries(...
                                'data', compressedData,...
                                'data_unit', 'unknown',...
                                'timestamps', timestamps,...  % Already a column vector (Nx1)
                                'description', [fieldName '_' innerFieldName]);
                        end
                    else
                        % If only one timestamp, use it as starting_time with default rate
                        
                        % For NWB, we need to ensure time is in the first dimension
                        % Now reintroduce compression with DataPipe, maintaining correct orientation
                        % The data is already properly oriented as a column vector
                        compressedData = types.untyped.DataPipe(...
                            'data', innerValue,...  % Already a column vector (Nx1)
                            'compressionLevel', 3,...
                            'axis', 1);  % axis=1 means time is in the first dimension
                        
                        ts = types.core.TimeSeries(...
                            'data', compressedData,...
                            'data_unit', 'unknown',...
                            'starting_time', timestamps(1),...
                            'starting_time_rate', 1.0,...
                            'description', [fieldName '_' innerFieldName]);
                        disp('  Using starting_time and starting_time_rate instead of timestamps (single timestamp)');
                    end
                    
                    % Add to NWB file
                    combinedName = [fieldName '_' innerFieldName];
                    if startsWith(combinedName, prefixToStrip)
                        % Remove the prefix
                        stripped = combinedName(length(prefixToStrip)+1:end);
                        if startsWith(stripped, '_')
                            stripped = stripped(2:end);
                        end
                        
                        % If it's an event with _times, keep that part
                        if endsWith(stripped, '_times')
                            strippedFieldName = stripped;
                        else
                            % For other fields, take just the last part
                            parts = strsplit(stripped, '_');
                            strippedFieldName = parts{end};
                        end
                    else
                        strippedFieldName = combinedName;
                    end
                    
                    nwb.acquisition.set(strippedFieldName, ts);
                    disp(' ');
                    disp(['FIELD: ' strippedFieldName]);
                    disp(['  Data shape: ' num2str(size(innerValue))]);
                    disp(['  Timestamps shape: ' num2str(size(timestamps))]);
                    disp('  STATUS: Successfully added to NWB path /acquisition/' + string(strippedFieldName));
                    foundNumeric = true;
                    break;
                end
            end
        end
        
        if ~foundNumeric
            % Store the warning message but don't display it yet
            warningMsg = ['Could not find suitable numeric data for ' fieldName '. Skipping.'];
            
            % First display the field header
            disp(' ');
            disp(['FIELD: ' fieldName]);
            
            % Now display the warning message
            disp('  WARNING: ' + string(warningMsg));
            
            % Continue with diagnostic info
            disp('  ## DIAGNOSTIC INFO ##');
            disp('  Structure contents:');
            
            % Display field names and their types/sizes
            innerFields = fieldnames(currentStruct);
            for k = 1:length(innerFields)
                innerFieldName = innerFields{k};
                innerValue = currentStruct.(innerFieldName);
                
                % Get type and size information
                valueType = class(innerValue);
                if isnumeric(innerValue)
                    sizeInfo = mat2str(size(innerValue));
                    if isempty(innerValue)
                        disp(['  - ' innerFieldName ': ' valueType ' (EMPTY) with size ' sizeInfo]);
                    else
                        % Show min/max for non-empty numeric data
                        minVal = num2str(min(innerValue(:)));
                        maxVal = num2str(max(innerValue(:)));
                        disp(['  - ' innerFieldName ': ' valueType ' with size ' sizeInfo ', range [' minVal ', ' maxVal ']']);
                        
                        % Check if data is 1D (vector) which might be why it's skipped
                        if size(innerValue, 1) <= 1
                            disp(['    NOTE: This field has only ' num2str(size(innerValue, 1)) ' row(s), which doesn''t meet the multi-dimensional requirement']);
                        end
                    end
                elseif isstruct(innerValue)
                    disp(['  - ' innerFieldName ': struct with ' num2str(numel(fieldnames(innerValue))) ' fields']);
                    % List the first few subfields to help with debugging
                    subFields = fieldnames(innerValue);
                    if ~isempty(subFields)
                        disp('    Subfields:');
                        for sf = 1:min(5, length(subFields))
                            disp(['      ' subFields{sf}]);
                        end
                        if length(subFields) > 5
                            disp(['      ... and ' num2str(length(subFields)-5) ' more fields']);
                        end
                    end
                elseif iscell(innerValue)
                    disp(['  - ' innerFieldName ': cell array with size ' mat2str(size(innerValue))]);
                    % Show content type of first few cells if not empty
                    if ~isempty(innerValue)
                        disp('    Sample cell contents:');
                        for sc = 1:min(3, numel(innerValue))
                            if iscell(innerValue) && numel(innerValue) >= sc
                                cellContent = innerValue{sc};
                                disp(['      Cell ' num2str(sc) ': ' class(cellContent) ' with size ' mat2str(size(cellContent))]);
                            end
                        end
                    end
                else
                    disp(['  - ' innerFieldName ': ' valueType ' with size ' mat2str(size(innerValue))]);
                    % Show actual content for title and comment fields
                    if ischar(innerValue) && (strcmpi(innerFieldName, 'title') || strcmpi(innerFieldName, 'comment'))
                        disp(['      Content: "' innerValue '"']);
                    end
                end
            end
            
            % Provide a hint about what's needed
            disp('  HINT: The converter requires numeric data with multiple rows (size(data,1) > 1)');
            disp('  STATUS: SKIPPED - Could not find suitable numeric data');
            % disp('-----------------------------------------------------------');
        end
    end
end

% Export to NWB format
nwbFilePath = [animal '_' signal '_' session '_' tag '.nwb'];
try
    nwbExport(nwb, nwbFilePath);
    disp(['Successfully exported NWB file to: ' nwbFilePath]);
catch err
    disp('Error exporting NWB file:');
    disp(err.message);
    nwbFilePath = '';
end
end

function [animal, signal, session, tag] = parseFileName(filePath)
% parseFileName - Extract components from the filename following the convention:
%                animalname_signal_session_tag  or  animalname_session_tag
%
% Input:
%   filePath - Full path or filename to parse
%
% Outputs:
%   animal  - Name of the animal
%   signal  - Type of signal recorded (empty string if not present)
%   session - Session number/identifier
%   tag     - Important tag identifier
%
% Examples:
%   [animal, signal, session, tag] = parseFileName('mouse1_VLS_42_control.mat')
%   animal => 'mouse1', signal => 'VLS', session => '42', tag => 'control'
%
%   [animal, signal, session, tag] = parseFileName('Jack_42_sham.mat')
%   animal => 'Jack', signal => '', session => '42', tag => 'sham'

    % Get just the filename without path and extension
    [~, fileName, ~] = fileparts(filePath);
    
    % Split the filename by underscores
    parts = strsplit(fileName, '_');
    
    % Verify we have either 3 or 4 components
    if ~ismember(length(parts), [3, 4])
        error('MATLAB:error', 'Invalid filename format. Expected: animalname_[signal_]session_tag');
    end
    
    % Extract components based on format
    animal = parts{1};
    
    if length(parts) == 4
        signal = parts{2};
        session = parts{3};
        tag = parts{4};
    else  % 3 components
        signal = '';  % No signal component
        session = parts{2};
        tag = parts{3};
    end
    
    % Basic validation
    if isempty(animal) || isempty(session) || isempty(tag)
        error('MATLAB:error', 'Animal, session, and tag components must be non-empty');
    end
end 
