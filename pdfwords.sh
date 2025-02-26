#!/usr/bin/env zsh
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
#
# This script is fully confined to a subshell so that it can be sourced and
# used interactively without affecting the shell environment.

pdfwords() {
  (
    # Enable strict error handling only in this subshell.
    set -euo pipefail

    # Check for required dependencies.
    for cmd in ocrmypdf pdftotext perl python3 awk; do
      if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required command '$cmd' not found. Please install it." >&2
        exit 1
      fi
    done

    # Ensure exactly two arguments are provided.
    if [[ $# -ne 2 ]]; then
      echo "Usage: pdfwords input.pdf|input_folder output.txt"
      exit 1
    fi

    local input="$1"
    local output="$2"
    local temp_file

    # Create a temporary file for storing extracted words.
    temp_file=$(mktemp) || { echo "Error: Unable to create temporary file." >&2; exit 1; }
    # Clean up the temporary file on exit.
    trap 'rm -f "$temp_file"' EXIT

    # Function to process a single PDF file.
    process_pdf() {
      local pdf="$1"
      echo "Processing: $pdf"
      local ocr_pdf="${pdf%.pdf}_ocr.pdf"

      # Run OCR; skip pages that already contain text.
      if ! ocrmypdf --skip-text --image-dpi 300 -l hin "$pdf" "$ocr_pdf"; then
        echo "Warning: OCRmyPDF failed for $pdf. Skipping this file." >&2
        return 1
      fi

      # Extract text from the OCRed PDF and extract words via Perl.
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
        exit 1
      fi
    elif [[ -f "$input" ]]; then
      process_pdf "$input"
    else
      echo "Error: '$input' is not a valid file or directory." >&2
      exit 1
    fi

    # Post-process the collected words:
    # 1. Remove duplicates (sort -u)
    # 2. Normalize Unicode (using Python)
    # 3. Prepend each word with its length, sort numerically, then remove the length.
    if ! sort -u "$temp_file" | \
         python3 -c "import sys,unicodedata; sys.stdout.writelines(unicodedata.normalize('NFKC', line) for line in sys.stdin)" | \
         awk '{print length, $0}' | sort -n | cut -d' ' -f2- > "$output"; then
      echo "Error: Post-processing of words failed." >&2
      exit 1
    fi

    echo "Processed output saved to: $output"
    exit 0
  )
}

# Export the function so that it is available in your interactive shell.
export -f pdfwords
