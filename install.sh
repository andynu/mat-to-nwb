#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting MATLAB to NWB Conversion Project setup..."

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "❌ Git is not installed. Please install git first."
    exit 1
fi

# Create a directory for the project if it doesn't exist
PROJECT_DIR="mat-to-nwb"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "📦 Cloning mat-to-nwb repository..."
    git clone https://github.com/andynu/mat-to-nwb.git "$PROJECT_DIR"
else
    echo "📦 Project directory already exists, skipping clone..."
fi

# Change to project directory
cd "$PROJECT_DIR"

# Clone MatNWB if it doesn't exist
if [ ! -d "matnwb" ]; then
    echo "📦 Cloning MatNWB repository..."
    git clone https://github.com/NeurodataWithoutBorders/matnwb.git
else
    echo "📦 MatNWB directory already exists, skipping clone..."
fi

echo "
✅ Setup complete!

Example usage:
   ./convert.sh /path/to/your_matlab_file.mat

For more examples and options, please refer to the README.md file.
" 