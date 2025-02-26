#!/bin/zsh
# pdfwords.sh - Process PDF files for OCR, extract words, and output a sorted list.
#
# This script handles a single PDF or a directory of PDFs.
# It uses OCRmyPDF to perform high-DPI OCR on pages missing text,
# extracts words via pdftotext and Perl, normalizes Unicode,
# removes duplicates, sorts words by length, and writes the output.
#
# Usage: pdfwords input.pdf|input_folder output.txt
#
# Requirements: ocrmypdf, pdftotext, perl, python3, awk

# ------------------------------------------------------------------------------
# Function: check_command
# Description: Verify that a required command is available.
# ------------------------------------------------------------------------------
check_command() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: Required command '$1' not found. Please install it." >&2
    return 1
  fi
}

# Check all required commands.
for cmd in ocrmypdf pdftotext perl python3 awk; do
  check_command "$cmd" || return 1
done

# ------------------------------------------------------------------------------
# Function: pdfwords
# Description: Process PDFs in a subshell to confine strict mode.
# ------------------------------------------------------------------------------
pdfwords() {
  (
    # Enable strict error handling within the subshell.
    set -euo pipefail

    if [[ $# -ne 2 ]]; then
      echo "Usage: pdfwords input.pdf|input_folder output.txt"
      exit 1
    fi

    local input="$1"
    local output="$2"
    local temp_file

    # Create a temporary file for storing extracted words.
    temp_file=$(mktemp) || { echo "Error: Unable to create temporary file." >&2; exit 1; }

    # ----------------------------------------------------------------------------
    # Function: process_pdf
    # Description: Process a single PDF file.
    # ----------------------------------------------------------------------------
    process_pdf() {
      local pdf="$1"
      echo "Processing: $pdf"
      local ocr_pdf="${pdf%.pdf}_ocr.pdf"

      # Run OCR; skip pages that already contain text.
      if ! ocrmypdf --skip-text --image-dpi 300 -l hin "$pdf" "$ocr_pdf"; then
        echo "Warning: OCRmyPDF failed for $pdf. Skipping this file." >&2
        return 1
      fi

      # Extract text and then words using Perl.
      if ! pdftotext -enc UTF-8 "$ocr_pdf" - | \
           perl -C -lne 'while (/(\p{L}+)/g){ print $1 }' >> "$temp_file"; then
        echo "Warning: Failed to extract text from $ocr_pdf. Skipping this file." >&2
        return 1
      fi
    }

    # Process the input: if it is a directory, iterate over all PDF files.
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
        exit 1
      fi
    elif [[ -f "$input" ]]; then
      process_pdf "$input"
    else
      echo "Error: '$input' is not a valid file or directory." >&2
      rm "$temp_file"
      exit 1
    fi

    # Post-process collected words:
    # 1. Remove duplicates
    # 2. Normalize Unicode (using Python)
    # 3. Prepend each word with its length, sort numerically, then remove the length.
    if ! sort -u "$temp_file" | \
         python3 -c "import sys,unicodedata; sys.stdout.writelines(unicodedata.normalize('NFKC', line) for line in sys.stdin)" | \
         awk '{print length, $0}' | sort -n | cut -d' ' -f2- > "$output"; then
      echo "Error: Post-processing of words failed." >&2
      rm "$temp_file"
      exit 1
    fi

    rm "$temp_file"
    echo "Processed output saved to: $output"
    exit 0
  )
}

# Expose the pdfwords function so that it is available in your interactive shell.
export -f pdfwords
