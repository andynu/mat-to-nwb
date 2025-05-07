# MATLAB to NWB Conversion Project

## Quick Setup

```bash
# Install using curl
curl -sSL https://raw.githubusercontent.com/andynu/mat-to-nwb/main/install.sh | bash

# Or download and run install script manually
curl -O https://raw.githubusercontent.com/andynu/mat-to-nwb/main/install.sh
bash install.sh
```

## Manual Setup

## Clone this repository
```bash
git clone https://github.com/andynu/mat-to-nwb.git
```

### MATLAB Dependencies
```bash
# Clone the MatNWB repository
git clone https://github.com/NeurodataWithoutBorders/matnwb.git
```

In MATLAB:
```matlab
% Add MatNWB to your path
addpath(genpath('/path/to/matnwb'));
```

## Scripts

### Conversion Scripts
- `convertMatToNwb.m`: Main conversion function that converts MATLAB data to NWB format
- `run_conversions.m`: Example script showing how to convert single or multiple files
- `analyze_matlab_file.m`: Utility to analyze and display MATLAB file structure
- `convert_matlab_to_nwb.py`: Python script for direct MATLAB v7.3 to NWB conversion

### Analysis Scripts
- `explore_nwb.py`: Python script to explore and visualize NWB file contents
- `visualize_nwb.py`: Python script for specific visualization of NWB data

## Data Structures

### MATLAB File Structure
The MATLAB files contain:
- Time series data (ChR2, X, Y, Z positions)
- Event markers (CamO, IRtrig, Juice, LampON/OFF, Lick, Start_Cu)
- Each data stream includes:
  - title and comment fields
  - resolution/interval information
  - time stamps
  - values (for time series)

### NWB File Structure
Generated NWB files contain:
- Acquisition data (time series)
- Event markers as time series
- Session metadata
- File identifier and description
- Session start time and reference time

## Usage Examples

### MATLAB Conversion
```matlab
% Convert a single file with default parameters
nwbFile = convertMatToNwb('./MATLABFiles/Jack_42_sham.mat');

% Convert a single file with custom description and experimenter
nwbFile = convertMatToNwb('./MATLABFiles/Jack_42_sham.mat', 'Session 42', 'Your name');

% Convert multiple files
files = {'Jack_42_sham.mat', 'Jack_43_sham.mat', 'Jack_45_sham.mat'};
for i = 1:length(files)
    nwbFile = convertMatToNwb(files{i}, ['Session ' num2str(i)], 'Your name');
end
```

### Batch Mode Conversion
To convert a single file using MATLAB's batch mode:
```bash
# Convert a single file
matlab -batch "convertMatToNwb('./MATLABFiles/Jack_42_sham.mat')"

# Convert a single file with custom description and experimenter
matlab -batch "convertMatToNwb('./MATLABFiles/Jack_42_sham.mat', 'Session 42', 'Your name')"
```

## Dependencies
- MATLAB
- MatNWB

## Other relevant tools
- nwbinspector - https://github.com/NeurodataWithoutBorders/nwbinspector
- VisiData - https://www.visidata.org/
