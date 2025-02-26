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
# used interactively without affecting your shell environment.

pdfwords() {
  # Use a subshell to isolate the environment.  This is already done in your
  # original script, but we'll make it extra explicit and consistent here.
  (
    # Enable strict error handling.
    set -euo pipefail

    # --- Dependency Check (Improved) ---
    local cmd
    for cmd in ocrmypdf pdftotext perl python3 awk; do
      if ! command -v "$cmd" >/dev/null 2>&1; then  # Redirect both stdout and stderr
        echo "Error: Required command '$cmd' not found. Please install it." >&2
        return 1  # Use 'return' within the subshell, not 'exit'
      fi
    done

    # --- Argument Validation (Improved) ---
    if (( $# != 2 )); then
      echo "Usage: pdfwords input.pdf|input_folder output.txt" >&2
      return 1
    fi
    local input="$1"
    local output="$2"
    local temp_file

    # --- Temporary File Handling (Improved) ---
    # Use mktemp -t for better portability (especially on macOS).  Explicitly
    # specify the directory and a prefix for easier debugging.  Use a more
    # robust error handling approach.
    temp_file=$(mktemp -t pdfwords.XXXXXX)
    if [[ ! -f "$temp_file" ]]; then
        echo "Error: Unable to create temporary file." >&2
        return 1
    fi
    # Use a function for cleanup to ensure it runs even on errors.
    local cleanup() {
      rm -f "$temp_file"
    }
    trap cleanup EXIT  # EXIT trap is triggered on normal exit, error exit, or signal

    # --- PDF Processing Function (Improved) ---
    local process_pdf() {
      local pdf="$1"
      echo "Processing: $pdf" >&2  # Output to stderr for better diagnostics
      local ocr_pdf="${pdf%.pdf}_ocr.pdf"

      # OCR with error handling.  Capture stderr for better debugging.
      if ! ocrmypdf --skip-text --image-dpi 300 -l hin "$pdf" "$ocr_pdf" 2>&1; then
        echo "Warning: OCRmyPDF failed for $pdf. See output above. Skipping." >&2
        return 1
      fi

      # Text extraction with error handling and stderr capture.
      if ! pdftotext -enc UTF-8 "$ocr_pdf" - | \
           perl -C -lne 'while (/(\p{L}+)/g){ print $1 }' >> "$temp_file" 2>&1; then
        echo "Warning: Failed to extract text from $ocr_pdf. See output above. Skipping." >&2
        return 1
      fi

      # Clean up the OCRed PDF after processing.
      rm -f "$ocr_pdf"
    }

    # --- Input Handling (Improved) ---
    if [[ -d "$input" ]]; then
      local pdf
      local found=0 # use (( found = 0 )) which is better
      # Use find for more robust directory traversal, handling filenames with spaces.
      find "$input" -maxdepth 1 -name "*.pdf" -print0 | while IFS= read -r -d $'\0' pdf; do
          (( found++ ))
          process_pdf "$pdf"
      done
       (( found == 0 )) && { echo "Error: No PDF files found in directory: $input" >&2; return 1; }

    elif [[ -f "$input" ]]; then
      process_pdf "$input"
    else
      echo "Error: '$input' is not a valid file or directory." >&2
      return 1
    fi

    # --- Post-Processing (Improved) ---
    # Use a single pipeline for efficiency and readability.  Redirect stderr
    # throughout the pipeline for comprehensive error reporting.
    if ! { sort -u "$temp_file" 2>&1 | \
         python3 -c "import sys,unicodedata; sys.stdout.writelines(unicodedata.normalize('NFKC', line) for line in sys.stdin)" 2>&1 | \
         awk '{print length, $0}' 2>&1 | sort -n 2>&1 | cut -d' ' -f2- 2>&1 > "$output"; } then
      echo "Error: Post-processing of words failed. See output above." >&2
      return 1
    fi

    echo "Processed output saved to: $output" >&2  # Output to stderr
    return 0 # return is more appropriate inside a subshell
  )  # End of subshell
}

# Don't export the function if it's being sourced.  Only export if the script
# is executed directly. This prevents unintended function exports when sourcing.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Sourced, do *not* export.
    :
else
    # Executed directly, *do* export (though this is probably not what you want
    # if you're sourcing the script into your .zshrc).
    export -f pdfwords
fi
