#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEXINPUTS="$SCRIPT_DIR:${TEXINPUTS:-}:"

# Default configuration
INPUT=""
OUTPUT=""
LAB_NUM="${LAB_NUM:-}"
TITLE="${LAB_TITLE:-}"
AUTHOR="${LAB_AUTHOR:-$(git config user.name 2>/dev/null || echo "Ilie Covali")}"
GROUP="${LAB_GROUP:-gr. FAF-243}"
VERIFIED="${LAB_VERIFIED:-}"
PDF_ENGINE="${PDF_ENGINE:-xelatex}"
TITLE_ONLY=false

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [INPUT] [OUTPUT]
       $(basename "$0") <title.pdf> <body.pdf> [output.pdf]

Build a lab report PDF with a custom LaTeX title page (labreport.cls)
and merge it with the pandoc-generated body PDF.

Positional arguments:
  INPUT                   Input file (.md or .pdf). Defaults to report.md
  OUTPUT                  Output PDF file. Defaults to report.pdf

Options:
  -i, --input <file>      Input Markdown or body PDF
  -o, --output <file>     Output PDF path
  -n, --number <num>      Lab work number (default: auto-detected or 1)
  -t, --title <text>      Lab work title (default: auto-detected)
  -a, --author <name>     Author name (default: "$AUTHOR")
  -g, --group <group>     Student group (default: "$GROUP")
  -v, --verified <name>   Supervisor/teacher name (default: "$VERIFIED")
  -e, --engine <engine>   Pandoc PDF engine (default: "$PDF_ENGINE")
      --title-only        Only generate the title page PDF
  -h, --help              Show this help message

Examples:
  $(basename "$0")                                # Builds report.md -> report.pdf with title
  $(basename "$0") -v "asist. univ. Zaica Maia"   # Set supervisor
  $(basename "$0") lab2.md lab2_report.pdf        # Specify input/output
  $(basename "$0") title.pdf body.pdf out.pdf     # Join two existing PDFs
EOF
}

# Parse options
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--input)
            INPUT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT="$2"
            shift 2
            ;;
        -n|--number|--lab-num)
            LAB_NUM="$2"
            shift 2
            ;;
        -t|--title)
            TITLE="$2"
            shift 2
            ;;
        -a|--author)
            AUTHOR="$2"
            shift 2
            ;;
        -g|--group)
            GROUP="$2"
            shift 2
            ;;
        -v|--verified)
            VERIFIED="$2"
            shift 2
            ;;
        -e|--engine)
            PDF_ENGINE="$2"
            shift 2
            ;;
        --title-only)
            TITLE_ONLY=true
            shift
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            show_help >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

merge_pdfs() {
    local title_pdf="$1"
    local body_pdf="$2"
    local out_pdf="$3"

    if command -v pdfunite >/dev/null 2>&1; then
        pdfunite "$title_pdf" "$body_pdf" "$out_pdf"
    elif command -v gs >/dev/null 2>&1; then
        gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile="$out_pdf" "$title_pdf" "$body_pdf"
    elif command -v qpdf >/dev/null 2>&1; then
        qpdf --empty --pages "$title_pdf" "$body_pdf" -- "$out_pdf"
    else
        echo "Error: No PDF merger found (requires pdfunite, gs, or qpdf)." >&2
        exit 1
    fi
}

# Case 1: Direct joining of two existing PDFs: script title.pdf body.pdf [out.pdf]
if [[ ${#POSITIONAL[@]} -ge 2 ]] && [[ "${POSITIONAL[0]}" == *.pdf ]] && [[ "${POSITIONAL[1]}" == *.pdf ]]; then
    TITLE_PDF="${POSITIONAL[0]}"
    BODY_PDF="${POSITIONAL[1]}"
    FINAL_OUT="${POSITIONAL[2]:-merged.pdf}"
    echo "Joining '$TITLE_PDF' + '$BODY_PDF' -> '$FINAL_OUT'..."
    merge_pdfs "$TITLE_PDF" "$BODY_PDF" "$FINAL_OUT"
    echo "Done: $FINAL_OUT"
    exit 0
fi

# Set positional inputs if provided
if [[ -z "$INPUT" ]] && [[ ${#POSITIONAL[@]} -ge 1 ]]; then
    INPUT="${POSITIONAL[0]}"
fi
if [[ -z "$OUTPUT" ]] && [[ ${#POSITIONAL[@]} -ge 2 ]]; then
    OUTPUT="${POSITIONAL[1]}"
fi

# Resolve default input
if [[ -z "$INPUT" ]]; then
    if [[ -f "report.md" ]]; then
        INPUT="report.md"
    elif [[ -f "report.pdf" ]]; then
        INPUT="report.pdf"
    else
        first_md=$(find . -maxdepth 1 -name "*.md" | head -n 1)
        if [[ -n "$first_md" ]]; then
            INPUT="$first_md"
        else
            echo "Error: No input file specified and no report.md found." >&2
            exit 1
        fi
    fi
fi

# Resolve default output
if [[ -z "$OUTPUT" ]]; then
    if [[ "$INPUT" == *.md ]]; then
        OUTPUT="${INPUT%.md}.pdf"
    elif [[ "$INPUT" == *.pdf ]]; then
        OUTPUT="${INPUT%.pdf}_with_title.pdf"
    else
        OUTPUT="report.pdf"
    fi
fi

# Auto-detect lab metadata if reading from markdown
if [[ "$INPUT" == *.md ]] && [[ -f "$INPUT" ]]; then
    if [[ -z "$LAB_NUM" ]]; then
        detected_num=$(grep -E -m 1 -i '(##|#)?[[:space:]]*Lab(oratory)?([[:space:]]*Work)?[[:space:]]*#?[0-9]+' "$INPUT" | sed -E 's/.*[Ll]ab(oratory)?([[:space:]]*Work)?[[:space:]]*#?([0-9]+).*/\3/' || true)
        if [[ -n "$detected_num" ]]; then
            LAB_NUM="$detected_num"
        fi
    fi

    if [[ -z "$TITLE" ]]; then
        detected_title=$(grep -E -m 1 -i '(##|#)?[[:space:]]*Lab(oratory)?([[:space:]]*Work)?[[:space:]]*#?[0-9]+[[:space:]]*[·:-]' "$INPUT" | sed -E 's/.*[Ll]ab(oratory)?([[:space:]]*Work)?[[:space:]]*#?[0-9]+[[:space:]]*[·:-][[:space:]]*(.*)/\3/' || true)
        if [[ -n "$detected_title" ]]; then
            # Clean markdown markers
            detected_title=$(echo "$detected_title" | sed -E 's/[#*_`]+$//' | sed -E 's/^[#*_`]+//' | tr -d '\r')
            TITLE="$detected_title"
        fi
    fi
fi

# Fallback defaults if still empty
LAB_NUM="${LAB_NUM:-1}"
TITLE="${TITLE:-Laboratory Work}"

# Create temporary workdir
TMP_DIR="$(mktemp -d /tmp/labreport_build.XXXXXX)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "=== Lab Report Build ==="
echo "Input:       $INPUT"
echo "Output:      $OUTPUT"
echo "Lab Number:  #$LAB_NUM"
echo "Title:       $TITLE"
echo "Author:      $AUTHOR"
echo "Group:       $GROUP"
echo "Verified:    ${VERIFIED:-<empty>}"
echo "========================"

# LaTeX escaping helper for basic special characters
escape_latex() {
    local text="$1"
    text="${text//&/\\&}"
    text="${text//%/\\%}"
    text="${text//\$/\\$}"
    text="${text//#/\\#}"
    text="${text//_/\\_}"
    echo "$text"
}

ESC_TITLE="$(escape_latex "$TITLE")"
ESC_AUTHOR="$(escape_latex "$AUTHOR")"
ESC_GROUP="$(escape_latex "$GROUP")"
ESC_VERIFIED="$(escape_latex "$VERIFIED")"

# Generate title page TeX file
cat << TEX > "$TMP_DIR/title.tex"
\documentclass{labreport}
\begin{document}
\labtitle{$LAB_NUM}{$ESC_TITLE}{$ESC_AUTHOR}{$ESC_GROUP}{$ESC_VERIFIED}
\end{document}
TEX

# Compile title page
echo "Compiling title page..."
if command -v pdflatex >/dev/null 2>&1; then
    pdflatex -interaction=nonstopmode -output-directory="$TMP_DIR" "$TMP_DIR/title.tex" > "$TMP_DIR/tex_stdout.log" 2>&1 || true
elif command -v xelatex >/dev/null 2>&1; then
    xelatex -interaction=nonstopmode -output-directory="$TMP_DIR" "$TMP_DIR/title.tex" > "$TMP_DIR/tex_stdout.log" 2>&1 || true
else
    echo "Error: Neither pdflatex nor xelatex found." >&2
    exit 1
fi

if [[ ! -f "$TMP_DIR/title.pdf" ]]; then
    echo "Error: Failed to compile title page. See log below:" >&2
    cat "$TMP_DIR/title.log" 2>/dev/null || cat "$TMP_DIR/tex_stdout.log" >&2
    exit 1
fi

# If user only wanted title page
if [[ "$TITLE_ONLY" = true ]]; then
    cp "$TMP_DIR/title.pdf" "$OUTPUT"
    echo "Generated title page: $OUTPUT"
    exit 0
fi

# Resolve or build body PDF
BODY_PDF=""
if [[ "$INPUT" == *.pdf ]]; then
    BODY_PDF="$INPUT"
elif [[ "$INPUT" == *.md ]]; then
    echo "Compiling Markdown body with pandoc (engine: $PDF_ENGINE)..."
    cat << 'TEX' > "$TMP_DIR/code_wrap.tex"
\usepackage{fvextra}
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,fontsize=\small,commandchars=\\\{\}}
TEX
    pandoc "$INPUT" -o "$TMP_DIR/body.pdf" \
        --pdf-engine="$PDF_ENGINE" \
        -V papersize=a4 \
        -V geometry:"left=25mm,right=25mm,top=25mm,bottom=25mm" \
        -H "$TMP_DIR/code_wrap.tex"
    BODY_PDF="$TMP_DIR/body.pdf"
else
    echo "Error: Unsupported input format '$INPUT'. Must be .md or .pdf" >&2
    exit 1
fi

# Join title and body
echo "Joining title page and report body..."
merge_pdfs "$TMP_DIR/title.pdf" "$BODY_PDF" "$TMP_DIR/final.pdf"

# Atomically replace destination
mv "$TMP_DIR/final.pdf" "$OUTPUT"

PAGES=$(pdfinfo "$OUTPUT" 2>/dev/null | awk '/^Pages:/ {print $2}' || echo "N/A")
echo "Successfully generated: $OUTPUT ($PAGES pages)"
