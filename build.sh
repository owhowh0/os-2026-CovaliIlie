#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
export TEXINPUTS="$SCRIPT_DIR:$PWD:${TEXINPUTS:-}:"

# Default configuration
INPUT=""
OUTPUT=""
LAB_NUM="${LAB_NUM:-}"
TITLE="${LAB_TITLE:-}"
AUTHOR="${LAB_AUTHOR:-$(git config user.name 2>/dev/null || echo "Ilie Covali")}"
GROUP="${LAB_GROUP:-gr. FAF-243}"
VERIFIED="${LAB_VERIFIED:-Reițman Patricia}"
PDF_ENGINE="${PDF_ENGINE:-xelatex}"
TITLE_ONLY=false

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TARGET | INPUT] [OUTPUT]
       $(basename "$0") <title.pdf> <body.pdf> [output.pdf]

Build lab report PDF with UTM LaTeX title page (labreport.cls)
and pandoc-generated body PDF.

Targets:
  all                     Build all labs (os-lab*) in repository
  <number> (e.g. 1, 2)    Build specific lab (os-lab<number>)
  <dir> (e.g. os-lab3)    Build specific lab directory
  <file> (.md or .pdf)    Build specific report file

Options:
  -i, --input <file>      Input Markdown or body PDF
  -o, --output <file>     Output PDF path
  -n, --number <num>      Lab work number (default: auto-detected)
  -t, --title <text>      Lab work title (default: auto-detected)
  -a, --author <name>     Author name (default: "$AUTHOR")
  -g, --group <group>     Student group (default: "$GROUP")
  -v, --verified <name>   Supervisor/teacher name (default: "$VERIFIED")
  -e, --engine <engine>   Pandoc PDF engine (default: "$PDF_ENGINE")
      --title-only        Only generate the title page PDF
  -h, --help              Show this help message

Examples:
  $(basename "$0")                     # Builds current lab or all labs
  $(basename "$0") all                 # Builds all labs
  $(basename "$0") 3                   # Builds os-lab3
  $(basename "$0") os-lab3/report.md   # Builds specific file
EOF
}

# Parse options
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    show_help
    exit 0
    ;;
  -i | --input)
    INPUT="$2"
    shift 2
    ;;
  -o | --output)
    OUTPUT="$2"
    shift 2
    ;;
  -n | --number | --lab-num)
    LAB_NUM="$2"
    shift 2
    ;;
  -t | --title)
    TITLE="$2"
    shift 2
    ;;
  -a | --author)
    AUTHOR="$2"
    shift 2
    ;;
  -g | --group)
    GROUP="$2"
    shift 2
    ;;
  -v | --verified)
    VERIFIED="$2"
    shift 2
    ;;
  -e | --engine)
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

# Helper to build a single report
build_report() {
  local in_file="$1"
  local out_file="${2:-}"
  local lab_num="${3:-$LAB_NUM}"
  local title="${4:-$TITLE}"
  local author="${5:-$AUTHOR}"
  local group="${6:-$GROUP}"
  local verified="${7:-$VERIFIED}"

  local workdir
  workdir="$(cd "$(dirname "$in_file")" && pwd)"
  local base_input
  base_input="$(basename "$in_file")"

  pushd "$workdir" >/dev/null

  # Auto-detect lab metadata if reading from markdown
  if [[ "$base_input" == *.md ]] && [[ -f "$base_input" ]]; then
    if [[ -z "$lab_num" ]]; then
      detected_num=$(grep -E -m 1 -i '(##|#)?[[:space:]]*Lab(oratory)?([[:space:]]*Work)?[[:space:]]*#?[0-9]+' "$base_input" | sed -E 's/.*[Ll]ab(oratory)?([[:space:]]*Work)?[[:space:]]*#?([0-9]+).*/\3/' || true)
      if [[ -n "$detected_num" ]]; then
        lab_num="$detected_num"
      fi
    fi

    if [[ -z "$title" ]]; then
      detected_title=$(grep -E -m 1 -i '(##|#)?[[:space:]]*Lab(oratory)?([[:space:]]*Work)?[[:space:]]*#?[0-9]+[[:space:]]*[·:-]' "$base_input" | sed -E 's/.*[Ll]ab(oratory)?([[:space:]]*Work)?[[:space:]]*#?[0-9]+[[:space:]]*[·:-][[:space:]]*(.*)/\3/' || true)
      if [[ -n "$detected_title" ]]; then
        detected_title=$(echo "$detected_title" | sed -E 's/[#*_`]+$//' | sed -E 's/^[#*_`]+//' | tr -d '\r')
        title="$detected_title"
      fi
    fi
  fi

  lab_num="${lab_num:-1}"
  title="${title:-Laboratory Work}"

  if [[ -z "$out_file" ]]; then
    if [[ "$base_input" == *.pdf ]]; then
      out_file="${base_input%.pdf}_with_title.pdf"
    else
      local clean_author clean_group
      clean_author="${author// /}"
      clean_group="${group// /}"
      clean_group="${clean_group#st.}"
      clean_group="${clean_group#gr.}"
      out_file="Lab${lab_num}_${clean_author}_${clean_group}.pdf"
    fi
  fi

  echo "=== Lab Report Build ==="
  echo "Directory:   $workdir"
  echo "Input:       $base_input"
  echo "Output:      $out_file"
  echo "Lab Number:  #$lab_num"
  echo "Title:       $title"
  echo "Author:      $author"
  echo "Group:       $group"
  echo "Verified:    $verified"
  echo "========================"

  # Escape LaTeX special chars helper
  escape_latex() {
    local text="$1"
    text="${text//&/\\&}"
    text="${text//%/\\%}"
    text="${text//\$/\\$}"
    text="${text//#/\\#}"
    text="${text//_/\\_}"
    echo "$text"
  }

  local esc_title esc_author esc_group esc_verified
  esc_title="$(escape_latex "$title")"
  esc_author="$(escape_latex "$author")"
  esc_group="$(escape_latex "$group")"
  esc_verified="$(escape_latex "$verified")"

  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/labreport_build.XXXXXX)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT INT TERM

  # Ensure class and logo are accessible in tmp_dir
  if [[ -f "$SCRIPT_DIR/LOGO_UTM.jpg" ]]; then
    cp "$SCRIPT_DIR/LOGO_UTM.jpg" "$tmp_dir/"
  elif [[ -f "LOGO_UTM.jpg" ]]; then
    cp "LOGO_UTM.jpg" "$tmp_dir/"
  fi
  if [[ -f "$SCRIPT_DIR/labreport.cls" ]]; then
    cp "$SCRIPT_DIR/labreport.cls" "$tmp_dir/"
  elif [[ -f "labreport.cls" ]]; then
    cp "labreport.cls" "$tmp_dir/"
  fi

  # Generate title page TeX file
  cat <<TEX >"$tmp_dir/title.tex"
\documentclass{labreport}
\begin{document}
\labtitle{$lab_num}{$esc_title}{$esc_author}{$esc_group}{$esc_verified}
\end{document}
TEX

  echo "Compiling title page..."
  if command -v pdflatex >/dev/null 2>&1; then
    pdflatex -interaction=nonstopmode -output-directory="$tmp_dir" "$tmp_dir/title.tex" >"$tmp_dir/tex_stdout.log" 2>&1 || true
  elif command -v xelatex >/dev/null 2>&1; then
    xelatex -interaction=nonstopmode -output-directory="$tmp_dir" "$tmp_dir/title.tex" >"$tmp_dir/tex_stdout.log" 2>&1 || true
  else
    echo "Error: Neither pdflatex nor xelatex found." >&2
    popd >/dev/null
    return 1
  fi

  if [[ ! -f "$tmp_dir/title.pdf" ]]; then
    echo "Error: Failed to compile title page. See log below:" >&2
    cat "$tmp_dir/title.log" 2>/dev/null || cat "$tmp_dir/tex_stdout.log" >&2
    popd >/dev/null
    return 1
  fi

  if [[ "$TITLE_ONLY" = true ]]; then
    cp "$tmp_dir/title.pdf" "$out_file"
    echo "Generated title page: $out_file"
    popd >/dev/null
    return 0
  fi

  local body_pdf=""
  if [[ "$base_input" == *.pdf ]]; then
    body_pdf="$base_input"
  elif [[ "$base_input" == *.md ]]; then
    echo "Compiling Markdown body with pandoc (engine: $PDF_ENGINE)..."
    cat <<'TEX' >"$tmp_dir/code_wrap.tex"
\usepackage{fvextra}
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,fontsize=\small,commandchars=\\\{\}}
TEX
    pandoc "$base_input" -o "$tmp_dir/body.pdf" \
      --pdf-engine="$PDF_ENGINE" \
      -V papersize=a4 \
      -V geometry:"left=25mm,right=25mm,top=25mm,bottom=25mm" \
      -H "$tmp_dir/code_wrap.tex"
    body_pdf="$tmp_dir/body.pdf"

  fi

  echo "Joining title page and report body..."
  merge_pdfs "$tmp_dir/title.pdf" "$body_pdf" "$tmp_dir/final.pdf"
  mv "$tmp_dir/final.pdf" "$out_file"

  local pages
  pages=$(pdfinfo "$out_file" 2>/dev/null | awk '/^Pages:/ {print $2}' || echo "N/A")
  echo "Successfully generated: $out_file ($pages pages)"
  rm -rf "$tmp_dir"
  trap - EXIT INT TERM
  popd >/dev/null
}

# Resolve target/input
TARGET="${POSITIONAL[0]:-}"
TARGET_OUT="${POSITIONAL[1]:-$OUTPUT}"

# Target = "all": loop through all lab directories
if [[ "$TARGET" == "all" ]]; then
  found=0
  for d in "$SCRIPT_DIR"/os-lab* "$SCRIPT_DIR"/lab*; do
    if [[ -d "$d" ]] && [[ -f "$d/report.md" ]]; then
      found=1
      echo ""
      build_report "$d/report.md" ""
    fi
  done
  if [[ $found -eq 0 ]]; then
    echo "No lab directories found matching os-lab* or lab*." >&2
    exit 1
  fi
  exit 0
fi

# Target = number (e.g. 1, 2, 3, 4)
if [[ -n "$TARGET" ]] && [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  if [[ -d "$SCRIPT_DIR/os-lab$TARGET" ]] && [[ -f "$SCRIPT_DIR/os-lab$TARGET/report.md" ]]; then
    build_report "$SCRIPT_DIR/os-lab$TARGET/report.md" "$TARGET_OUT"
    exit 0
  elif [[ -d "$SCRIPT_DIR/lab$TARGET" ]] && [[ -f "$SCRIPT_DIR/lab$TARGET/report.md" ]]; then
    build_report "$SCRIPT_DIR/lab$TARGET/report.md" "$TARGET_OUT"
    exit 0
  fi
fi

# Target = directory
if [[ -n "$TARGET" ]] && [[ -d "$TARGET" ]]; then
  if [[ -f "$TARGET/report.md" ]]; then
    build_report "$TARGET/report.md" "$TARGET_OUT"
    exit 0
  else
    echo "Error: Directory '$TARGET' has no report.md" >&2
    exit 1
  fi
fi

# Target = specific file
if [[ -n "$TARGET" ]] && [[ -f "$TARGET" ]]; then
  build_report "$TARGET" "$TARGET_OUT"
  exit 0
fi

# No target given: check if current directory has report.md
if [[ -f "report.md" ]]; then
  build_report "report.md" "$TARGET_OUT"
  exit 0
fi

# In root directory with no arguments: build all labs
if [[ -d "$SCRIPT_DIR/os-lab1" ]] || [[ -d "$SCRIPT_DIR/os-lab2" ]] || [[ -d "$SCRIPT_DIR/os-lab3" ]]; then
  echo "No target specified. Building all discovered labs..."
  for d in "$SCRIPT_DIR"/os-lab*; do
    if [[ -d "$d" ]] && [[ -f "$d/report.md" ]]; then
      echo ""
      build_report "$d/report.md" ""
    fi
  done
  exit 0
fi

echo "Error: Could not determine what to build. Specify a file, directory, or 'all'." >&2
show_help >&2
exit 1
