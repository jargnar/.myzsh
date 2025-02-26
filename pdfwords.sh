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

#!/usr/bin/env zsh
# pdfwords.sh - Process PDF files for OCR, extract words or bigrams, and output a sorted list.

pdfwords() {
  (
    set -euo pipefail

    local cmd
    for cmd in ocrmypdf pdftotext perl python3 awk; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found. Please install it." >&2
        return 1
      fi
    done

    # Parse command-line options.
    local bigrams_flag=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --bigrams)
          bigrams_flag=true
          shift
          ;;
        *)
          break  # Stop parsing options when a non-option argument is encountered.
          ;;
      esac
    done
     # Check for required input and output arguments after processing options.
    if (( $# != 2 )); then
        echo "Usage: pdfwords [--bigrams] input.pdf|input_folder output.txt" >&2
        return 1
    fi

    local input="$1"
    local output="$2"
    local temp_file

    temp_file=$(mktemp -t pdfwords.XXXXXX)
    if [[ ! -f "$temp_file" ]]; then
        echo "Error: Unable to create temporary file." >&2
        return 1
    fi
    local cleanup() {
      rm -f "$temp_file"
    }
    trap cleanup EXIT

    local process_pdf() {
      local pdf="$1"
      echo "Processing: $pdf" >&2
      local ocr_pdf="${pdf%.pdf}_ocr.pdf"

      if ! ocrmypdf --skip-text --image-dpi 300 -l hin "$pdf" "$ocr_pdf" 2>&1; then
        echo "Warning: OCRmyPDF failed for $pdf. See output above. Skipping." >&2
        return 1
      fi

      # Extract text and process based on the --bigrams flag.
      if "$bigrams_flag"; then
        # Bigram extraction.
        if ! pdftotext -enc UTF-8 "$ocr_pdf" - | \
             perl -C -lne '
               s/[^\p{L}]+/ /g;
               my @words = split(/\s+/);
               for (my $i = 0; $i < @words - 1; $i++) {
                 print lc($words[$i] . " " . $words[$i+1]);
               }
             ' >> "$temp_file" 2>&1; then
          echo "Warning: Failed to extract text or generate bigrams from $ocr_pdf. See output above. Skipping." >&2
          return 1
        fi
      else
        # Single word extraction (original logic).
        if ! pdftotext -enc UTF-8 "$ocr_pdf" - | \
             perl -C -lne 'while (/(\p{L}+)/g){ print $1 }' >> "$temp_file" 2>&1; then
          echo "Warning: Failed to extract text from $ocr_pdf. See output above. Skipping." >&2
          return 1
        fi
      fi

      rm -f "$ocr_pdf"
    }

    if [[ -d "$input" ]]; then
      local pdf
      local found=0
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

    # Post-processing (conditional based on --bigrams).
    if "$bigrams_flag"; then
        # Bigram post-processing.
        if ! { sort -u "$temp_file" 2>&1 | \
             python3 -c "import sys,unicodedata; sys.stdout.writelines(unicodedata.normalize('NFKC', line) for line in sys.stdin)" 2>&1 | \
             sort 2>&1 > "$output"; } then
          echo "Error: Post-processing of bigrams failed. See output above." >&2
          return 1
        fi
    else
       # Single word post-processing (original logic).
        if ! { sort -u "$temp_file" 2>&1 | \
             python3 -c "import sys,unicodedata; sys.stdout.writelines(unicodedata.normalize('NFKC', line) for line in sys.stdin)" 2>&1 | \
             awk '{print length, $0}' 2>&1 | sort -n 2>&1 | cut -d' ' -f2- 2>&1 > "$output"; } then
          echo "Error: Post-processing of words failed. See output above." >&2
          return 1
        fi
    fi

    if "$bigrams_flag"; then
        echo "Processed bigram output saved to: $output" >&2
    else
        echo "Processed output saved to: $output" >&2
    fi
    return 0
  )
}
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    :
else
    export -f pdfwords
fi
