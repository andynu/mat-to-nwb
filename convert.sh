#!/bin/bash
# Script to convert a MAT file to NWB format
set -e  # Exit immediately if a command exits with a non-zero status
set -x  # Print commands and their arguments as they are executed

# Check if a filename was provided
if [ $# -eq 0 ]; then
  echo "Error: No filename provided"
  echo "Usage: $0 <filename.mat>"
  exit 1
fi

file="$1"

# Check if the file exists
if [ ! -f "$file" ]; then
  echo "Error: File '$file' not found"
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
  echo "Warning: Output file '$nwb_file' already exists."
  read -p "Do you want to remove it and continue? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Removing existing file '$nwb_file'..."
    rm -f "$nwb_file"
  else
    echo "Conversion cancelled."
    exit 0
  fi
fi

# Run the MATLAB conversion script
matlab -batch "convertMatToNwb('$file')"
