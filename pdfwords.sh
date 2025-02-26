#!/bin/zsh
# pdfwords.sh - Process PDF files for OCR, extract words, and output a sorted list.
#
# This script can handle either a single PDF file or a directory containing PDFs.
# It uses OCRmyPDF to perform high-DPI OCR on pages missing text, extracts words,
# normalizes Unicode, removes duplicates, sorts them by length, and writes the output.
#
# Usage: pdfwords input.pdf|input_folder output.txt
#
# Requirements: ocrmypdf, pdftotext, perl, python3, awk

# Enable strict error handling.
set -euo pipefail

# ------------------------------------------------------------------------------
# Function: check_command
# Description: Verify that a required command is available.
# ------------------------------------------------------------------------------
check_command() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: Required command '$1' not found. Please install it." >&2
    exit 1
  fi
}

# Check all required commands.
for cmd in ocrmypdf pdftotext perl python3 awk; do
  check_command "$cmd"
done

# ------------------------------------------------------------------------------
# Function: process_pdf
# Description: Process a single PDF file:
#   - Runs OCR (skipping pages with text already)
#   - Extracts words via pdftotext and Perl
#   - Appends the results to the global temporary file.
#
# Parameters:
#   $1 - The path to the PDF file.
# ------------------------------------------------------------------------------
process_pdf() {
  local pdf="$1"
  echo "Processing: $pdf"
  local ocr_pdf="${pdf%.pdf}_ocr.pdf"

  # Run OCR; skip pages with an existing text layer.
  if ! ocrmypdf --skip-text --image-dpi 300 -l hin "$pdf" "$ocr_pdf"; then
    echo "Warning: OCRmyPDF failed for $pdf. Skipping this file." >&2
    return 1
  fi

  # Extract text and then extract words using Perl.
  if ! pdftotext -enc UTF-8 "$ocr_pdf" - | \
       perl -C -lne 'while (/(\p{L}+)/g){ print $1 }' >> "$temp_file"; then
    echo "Warning: Failed to extract text from $ocr_pdf. Skipping this file." >&2
    return 1
  fi
}

# ------------------------------------------------------------------------------
# Function: pdfwords
# Description: Main function to process PDFs.
#   - Accepts either a single PDF or a directory of PDFs.
#   - Collects extracted words into a temporary file.
#   - Normalizes Unicode, removes duplicates, and sorts by word length.
#
# Usage: pdfwords input.pdf|input_folder output.txt
# ------------------------------------------------------------------------------
pdfwords() {
  if [[ $# -ne 2 ]]; then
    echo "Usage: pdfwords input.pdf|input_folder output.txt"
    return 1
  fi

  local input="$1"
  local output="$2"

  # Create a temporary file for storing extracted words.
  temp_file=$(mktemp) || { echo "Error: Unable to create temporary file." >&2; return 1; }

  # Process input: if it's a directory, iterate over all PDF files.
  if [[ -d "$input" ]]; then
    local found=0
    for pdf in "$input"/*.pdf; do
      if [[ -f "$pdf" ]]; then
        found=1
        process_pdf "$pdf"
      fi
    done
    if [[ $found -eq 0 ]]; then
      echo "Error: No PDF files found in directory: $input" >&2
      rm "$temp_file"
      return 1
    fi
  elif [[ -f "$input" ]]; then
    process_pdf "$input"
  else
    echo "Error: '$input' is not a valid file or directory." >&2
    rm "$temp_file"
    return 1
  fi

  # Post-process collected words:
  # 1. Remove duplicates (sort -u)
  # 2. Normalize Unicode using Python
  # 3. Prepend each word with its length, sort numerically, then remove the length.
  if ! sort -u "$temp_file" | \
       python3 -c "import sys, unicodedata; sys.stdout.writelines(unicodedata.normalize('NFKC', line) for line in sys.stdin)" | \
       awk '{print length, $0}' | sort -n | cut -d' ' -f2- > "$output"; then
    echo "Error: Post-processing of words failed." >&2
    rm "$temp_file"
    return 1
  fi

  rm "$temp_file"
  echo "Processed output saved to: $output"
}

# Expose the pdfwords function when sourcing this script.
export -f pdfwords
