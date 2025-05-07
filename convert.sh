#!/bin/bash
# Script to convert a MAT file to NWB format
set -e  # Exit immediately if a command exits with a non-zero status
#set -x  # Print commands and their arguments as they are executed

# Check if a filename was provided
if [ $# -eq 0 ]; then
    echo "❌ Please provide a MATLAB file to convert"
    echo "Usage: $0 <filename.mat> [session_description] [experimenter]"
    exit 1
fi

file="$1"
session_desc="${2:-}"  # Optional session description
experimenter="${3:-}"  # Optional experimenter name

# Check if the file exists
if [ ! -f "$file" ]; then
    echo "❌ File not found: $file"
    exit 1
fi

# Extract filename components to determine the output NWB filename
filename=$(basename "$file")
filename_noext="${filename%.*}"
IFS='_' read -r animal signal session tag <<< "$filename_noext"

# Handle the case where there's no signal component (3 parts instead of 4)
if [ -z "$tag" ]; then
    tag="$session"
    session="$signal"
    signal=""
fi

# Construct the expected output NWB filename
if [ -z "$signal" ]; then
    nwb_file="${animal}_${session}_${tag}.nwb"
else
    nwb_file="${animal}_${signal}_${session}_${tag}.nwb"
fi

# Check if the output NWB file already exists
if [ -f "$nwb_file" ]; then
    echo "⚠️ Warning: Output file '$nwb_file' already exists."
    read -p "Do you want to remove it and continue? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "🗑️ Removing existing file '$nwb_file'..."
        rm -f "$nwb_file"
    else
        echo "❌ Conversion cancelled."
        exit 0
    fi
fi

echo "🚀 Converting $file to NWB format..."

# Build the MATLAB command with optional parameters
matlab_cmd="addpath(genpath('$(dirname "$0")/matnwb')); convertMatToNwb('$file'"
if [ ! -z "$session_desc" ]; then
    matlab_cmd="$matlab_cmd, '$session_desc'"
    if [ ! -z "$experimenter" ]; then
        matlab_cmd="$matlab_cmd, '$experimenter'"
    fi
fi
matlab_cmd="$matlab_cmd)"

# Run the MATLAB conversion script and capture its exit status
if matlab -batch "$matlab_cmd"; then
    # Check if the output file was actually created
    if [ -f "$nwb_file" ]; then
        echo "✅ Conversion successful! Output saved as $nwb_file"
    else
        echo "❌ Conversion failed: Output file was not created"
        exit 1
    fi
else
    echo "❌ Conversion failed: MATLAB returned an error"
    exit 1
fi
