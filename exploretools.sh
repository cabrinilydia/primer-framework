#!/usr/bin/env bash
###############################################################################
# explore_tools.sh
#
# Hands-on tool explorer for the Primer Design Framework.
# Runs each CLI tool from the tool table with a small SARS-CoV-2 example
# so you can see EXACTLY what goes in and what comes out.
#
# Usage:
#   chmod +x explore_tools.sh
#   ./explore_tools.sh            # run all stages
#   ./explore_tools.sh stage1     # run only Stage 1
#   ./explore_tools.sh stage2     # run only Stage 2
#   ./explore_tools.sh stage3     # run only Stage 3
###############################################################################

set -u
# Note: we intentionally do NOT use 'set -e' or 'set -o pipefail'
# because grep|head pipelines produce harmless SIGPIPE errors
# and we want the script to keep going if a tool is missing.

FASTA="test5.fasta"
OUTDIR="tool_outputs"
mkdir -p "$OUTDIR"

# ── Colors for pretty output ────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

banner()  { echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $1${NC}"; echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}\n"; }
section() { echo -e "\n${YELLOW}── $1 ──${NC}\n"; }
show()    { echo -e "${GREEN}$1${NC}"; }
warn()    { echo -e "${RED}$1${NC}"; }

###############################################################################
# STAGE 1: INPUT / ALIGNMENT
###############################################################################
stage1() {
banner "STAGE 1 — INPUT / ALIGNMENT"

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: MAFFT
# ─────────────────────────────────────────────────────────────────────────────
section "1a) MAFFT — Multiple Sequence Alignment"

show "INPUT:  A multi-FASTA file with 2+ sequences"
echo "File: $FASTA"
echo "First 5 lines:"
head -5 "$FASTA"
echo "..."
echo "Sequence count: $(grep -c '^>' "$FASTA")"

echo ""
show "COMMAND:"
echo "  mafft --auto --thread -1 $FASTA > $OUTDIR/mafft_aligned.fasta"

if command -v mafft &>/dev/null; then
    mafft --auto --thread -1 "$FASTA" > "$OUTDIR/mafft_aligned.fasta" 2>"$OUTDIR/mafft_stderr.log"

    show "OUTPUT: Aligned FASTA (gaps shown as '-' characters)"
    echo "File: $OUTDIR/mafft_aligned.fasta"
    echo "First 10 lines:"
    head -10 "$OUTDIR/mafft_aligned.fasta"
    echo "..."
    echo ""
    echo "Notice the '-' gap characters that MAFFT inserted to align sequences."
    echo "Output size: $(wc -c < "$OUTDIR/mafft_aligned.fasta") bytes"
else
    warn "MAFFT not installed. Install: brew install mafft (Mac) or sudo apt install mafft (Linux)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: Clustal Omega
# ─────────────────────────────────────────────────────────────────────────────
section "1b) Clustal Omega — Alternative MSA tool"

show "INPUT:  Same multi-FASTA file (needs 3+ sequences)"
show "COMMAND:"
echo "  clustalo -i $FASTA -o $OUTDIR/clustalo_aligned.fasta --threads=4 --force"

if command -v clustalo &>/dev/null; then
    clustalo -i "$FASTA" -o "$OUTDIR/clustalo_aligned.fasta" --threads=4 --force 2>"$OUTDIR/clustalo_stderr.log"

    show "OUTPUT: Aligned FASTA (same format as MAFFT, different algorithm)"
    head -10 "$OUTDIR/clustalo_aligned.fasta"
    echo "..."
else
    warn "Clustal Omega not installed. Install: brew install clustal-omega (Mac) or sudo apt install clustalo (Linux)"
fi

echo ""
show "STAGE 1 SUMMARY:"
echo "  Input format:  Multi-FASTA (unaligned sequences)"
echo "  Output format: Multi-FASTA (aligned, with gap characters '-')"
echo "  Both tools produce the SAME output format → swappable!"
}

###############################################################################
# STAGE 2: CANDIDATE GENERATION
###############################################################################
stage2() {
banner "STAGE 2 — CANDIDATE GENERATION"

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: Primer3 (primer3_core)
# ─────────────────────────────────────────────────────────────────────────────
section "2a) Primer3 (primer3_core) — Gold standard primer design"

# We need a template sequence. Use a ~1kb region from the first sequence.
# Write to temp file first to avoid SIGPIPE from grep|head pipes.
python3 -c "
with open('$FASTA') as f:
    seq = []
    started = False
    for line in f:
        if line.startswith('>'):
            if started: break
            started = True
            continue
        seq.append(line.strip())
print(''.join(seq)[:1000])
" > "$OUTDIR/template_seq.txt" 2>/dev/null
TEMPLATE=$(cat "$OUTDIR/template_seq.txt")

show "INPUT: Boulder-IO format (a key=value text format)"
echo "Creating input file..."

cat > "$OUTDIR/primer3_input.txt" <<BOULDER
SEQUENCE_ID=SARS2_region
SEQUENCE_TEMPLATE=$TEMPLATE
PRIMER_TASK=generic
PRIMER_PICK_LEFT_PRIMER=1
PRIMER_PICK_RIGHT_PRIMER=1
PRIMER_NUM_RETURN=5
PRIMER_MIN_SIZE=18
PRIMER_OPT_SIZE=20
PRIMER_MAX_SIZE=25
PRIMER_MIN_TM=57.0
PRIMER_OPT_TM=60.0
PRIMER_MAX_TM=63.0
PRIMER_MIN_GC=40.0
PRIMER_MAX_GC=60.0
PRIMER_PRODUCT_SIZE_RANGE=100-300
=
BOULDER

echo "File: $OUTDIR/primer3_input.txt"
echo "Contents:"
cat "$OUTDIR/primer3_input.txt" | head -16
echo "(template sequence truncated for display)"

echo ""
show "COMMAND:"
echo "  primer3_core < $OUTDIR/primer3_input.txt > $OUTDIR/primer3_output.txt"

if command -v primer3_core &>/dev/null; then
    primer3_core < "$OUTDIR/primer3_input.txt" > "$OUTDIR/primer3_output.txt"

    show "OUTPUT: Boulder-IO key=value pairs with primer results"
    echo "File: $OUTDIR/primer3_output.txt"
    echo ""
    echo "Key output fields:"
    echo "─────────────────"
    grep -E "^PRIMER_(PAIR_NUM_RETURNED|LEFT_0|RIGHT_0)" "$OUTDIR/primer3_output.txt" || true
    echo ""
    echo "Full output (first 30 lines):"
    head -30 "$OUTDIR/primer3_output.txt"
    echo "..."
else
    warn "primer3_core not installed. Install: brew install primer3 (Mac) or sudo apt install primer3 (Linux)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: primer3-py (Python bindings)
# ─────────────────────────────────────────────────────────────────────────────
section "2b) primer3-py — Python API alternative"

show "INPUT: Python dict with same parameters as Boulder-IO"
show "COMMAND: (Python script)"

cat > "$OUTDIR/primer3py_demo.py" <<'PYEOF'
#!/usr/bin/env python3
"""Demo: primer3-py input/output"""
try:
    import primer3
except ImportError:
    print("primer3-py not installed. Install: pip install primer3-py")
    exit(0)

import json

# INPUT: Python dictionary
seq_args = {
    'SEQUENCE_ID': 'SARS2_demo',
    'SEQUENCE_TEMPLATE': 'ATTAAAGGTTTATACCTTCCCAGGTAACAAACCAACCAACTTTCGATCTCTTGTAGATCTGTTCTCTAAACGAACTTTAAAATCTGTGTGGCTGTCACTCGGCTGCATGCTTAGTGCACTCACGCAGTATAATTAATAACTAATTACTGTCGTTGACAGGACACGAGTAACTCGTCTATCTTCTGCAGGCTGCTTACGGTTTCGTCCGTGTTGCAGCCGATCATCAGCACATCTAGGTTTCGTCCGGGTGTGACCGAAAGGTAAGATGGAGAGCCTTGTCCCTGGTTTCAACGAGAAAACACACGTCCAACTCAGTTTGCCTGTTTTACAGGTTCGCGACGTGCTCGTACGTGGCTTTGGAGACTCCGTGGAGGAGGTCTTATCAGAGGCACGTCAACATCTTAAAGATGGCACTTGTGGCTTAGTAGAAGTTGAAAAAGGCGTTTTGCCTCAACTTGAACAGCCCTATGTGTTCATCAAACGTTCGGATGCTCGAACTGCACCTCATGGTCATGTTATGGTTGAGCTGGTAGCAGAACTCGAAGGCATTCAGTACGGTCGTAGTGGTGAGACACTTGGTGTCCTTGTCCCTCATGTGGGCGAAATACCAGTGGCTTACCGCAAGGTTCTTCTTCGTAAGAACGGTAATAAAGGAGCTGGTGGCCATAGTTACGGCGCCGATCTAAAGTCATTTGACTTAGGCGACGAGCTTGGCACTGATCCTTATGAAGATTTTCAAGAAAACTGGAACACTAAACATAGCAGTGGTGTTACCCGTGAACTCATGCGTGAGCTTAACGGAGGGGCATACACTCGCTATGTCGATAACAACTTCTGTGGCCCTGATGGCTACCCTCTTGAGTGCATTAAAGACCTTCTAGCACGTGCTGGTAAAGCTTCATGCACTTTGTCCGAACAACTGGACTTTATTGACACTAAGAGGGGTGTATACTGCTGCCGTGAACATGAGCATGAAATTGCTTGGTACACGGAACGTTCTGAAAAGAGCTATGAATTGCAGACACCTTTTGAAATTAAATTGGCAAAGAAATTTGACACC',
}

global_args = {
    'PRIMER_NUM_RETURN': 3,
    'PRIMER_MIN_SIZE': 18,
    'PRIMER_OPT_SIZE': 20,
    'PRIMER_MAX_SIZE': 25,
    'PRIMER_MIN_TM': 57.0,
    'PRIMER_OPT_TM': 60.0,
    'PRIMER_MAX_TM': 63.0,
    'PRIMER_PRODUCT_SIZE_RANGE': [[100, 300]],
}

print("INPUT (Python dict):")
print(f"  seq_args keys: {list(seq_args.keys())}")
print(f"  global_args keys: {list(global_args.keys())}")
print()

# Run primer3
result = primer3.design_primers(seq_args, global_args)

print("OUTPUT (Python dict with all results):")
print(f"  Pairs returned: {result.get('PRIMER_PAIR_NUM_RETURNED', 0)}")
print()

for i in range(min(3, result.get('PRIMER_PAIR_NUM_RETURNED', 0))):
    print(f"  Pair {i}:")
    print(f"    Left seq:  {result.get(f'PRIMER_LEFT_{i}_SEQUENCE', 'N/A')}")
    print(f"    Left Tm:   {result.get(f'PRIMER_LEFT_{i}_TM', 'N/A')}")
    print(f"    Right seq: {result.get(f'PRIMER_RIGHT_{i}_SEQUENCE', 'N/A')}")
    print(f"    Right Tm:  {result.get(f'PRIMER_RIGHT_{i}_TM', 'N/A')}")
    print(f"    Product:   {result.get(f'PRIMER_PAIR_{i}_PRODUCT_SIZE', 'N/A')} bp")
    print()

# Also show Tm calculation
tm = primer3.calc_tm("ACGTACGTACGTACGTACGT")
print(f"  Bonus — calc_tm('ACGTACGTACGTACGTACGT') = {tm:.1f}°C")
PYEOF

show "OUTPUT: Structured dict with primer sequences, Tm, positions"
python3 "$OUTDIR/primer3py_demo.py" 2>/dev/null || warn "  (primer3-py not available — see script at $OUTDIR/primer3py_demo.py)"

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: EMBOSS eprimer3
# ─────────────────────────────────────────────────────────────────────────────
section "2c) EMBOSS eprimer3 — EMBOSS wrapper around Primer3"

show "INPUT: Single-sequence FASTA file"

python3 -c "
with open('$FASTA') as f:
    lines = f.readlines()
print(lines[0].strip())
seq = []
for line in lines[1:]:
    if line.startswith('>'): break
    seq.append(line.strip())
print(''.join(seq)[:1000])
" > "$OUTDIR/single_seq.fasta" 2>/dev/null

show "COMMAND:"
echo "  eprimer3 -sequence $OUTDIR/single_seq.fasta -outfile $OUTDIR/eprimer3_output.txt -numreturn 5 -mintm 50 -opttm 58 -maxtm 68 -minsize 17 -optsize 20 -maxsize 30 -mingc 20 -maxgc 80 -prange 100-300 -maxdifftm 5 -explainflag Y"

if command -v eprimer3 &>/dev/null; then
    eprimer3 \
      -sequence "$OUTDIR/single_seq.fasta" \
      -outfile "$OUTDIR/eprimer3_output.txt" \
      -numreturn 5 \
      -mintm 50 \
      -opttm 58 \
      -maxtm 68 \
      -minsize 17 \
      -optsize 20 \
      -maxsize 30 \
      -mingc 20 \
      -maxgc 80 \
      -prange 100-300 \
      -maxdifftm 5 \
      -explainflag Y 2>/dev/null

    show "OUTPUT: EMBOSS primer report"
    head -80 "$OUTDIR/eprimer3_output.txt"

    echo ""
    echo "Relevant lines:"
    grep -n "FORWARD PRIMER\|REVERSE PRIMER\|PRODUCT SIZE\|Start" "$OUTDIR/eprimer3_output.txt" || true

    if grep -q "Amplimer" "$OUTDIR/eprimer3_output.txt" || grep -Eq '^[[:space:]]*[0-9]+[[:space:]]+[0-9]+' "$OUTDIR/eprimer3_output.txt"; then
        echo ""
        echo "Primer rows detected in eprimer3 output."
    else
        echo ""
        warn "eprimer3 ran, but this demo did not show usable primer rows under the current settings."
        echo "Note: primer3_core successfully found primer pairs on the same template."
        echo "This suggests wrapper/output-format behavior rather than absence of valid primers."
    fi
else
    warn "eprimer3 not installed. Install EMBOSS: brew install emboss (Mac) or sudo apt install emboss (Linux)"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: PMPrimer
# ─────────────────────────────────────────────────────────────────────────────
section "2d) PMPrimer — Pan-genome multiplex primer design"

show "INPUT: FASTA file (aligned or unaligned genomes)"
echo "  PMPrimer takes multiple genomes and designs primers that amplify"
echo "  conserved regions across all of them."
echo ""
show "COMMAND:"
echo "  pmprimer -f genomes.fasta -a threshold:0.85 gaps:1.0 merge primer2 tm:45.0 -e minlen:150 maxlen:1500 save"
echo ""

if command -v pmprimer &>/dev/null; then
    show "PMPrimer is installed."
    echo "Help output:"
    pmprimer -h 2>&1 | head -20
    echo ""
    echo "Demo note: full PMPrimer run not executed here because it expects its own workflow/options"
    echo "and may require more suitable input plus optional external tools (e.g. MUSCLE/BLAST)."
    echo ""
    echo "Expected output:"
    echo "  - result tables / CSV-like saved outputs with primer candidates"
    echo "  - conserved-region and evaluation summaries"
else
    warn "PMPrimer not installed."
    echo "  Expected output: primer design result tables and evaluation summaries"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: primerdiffer
# ─────────────────────────────────────────────────────────────────────────────
section "2e) primerdiffer — Discriminatory primer design between genomes"

show "INPUT: Two genome FASTA files (target vs. non-target) + optional VCF"
echo "  Designs primers that amplify the target genome but NOT the non-target."
echo ""
show "COMMAND:"
echo "  primerdesign.py -g1 target.fasta -g2 nontarget.fasta -pos \"Chr1:1-1000\" --interval 400"
echo ""

if command -v primerdesign.py &>/dev/null; then
    show "primerdiffer is installed via primerdesign.py"
    # Would need two separate FASTA files for a real demo
    echo "  Live demo skipped: requires two real genome FASTA files plus a biologically meaningful -pos region."
else
    warn "primerdiffer not installed."
    echo "  Expected output: TSV/CSV of discriminatory primer pairs with:"
    echo "    - primer sequences, Tm, GC%, mismatch positions"
    echo "    - specificity scores against non-target genome"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: Primer Prospector
# ─────────────────────────────────────────────────────────────────────────────
section "2f) Primer Prospector — Amplicon coverage analysis"

show "INPUT: Aligned FASTA (MSA from Stage 1)"
echo "  Analyzes primer binding sites across aligned sequences to maximize"
echo "  coverage of a diverse set of organisms."
echo ""
show "COMMANDS:"
echo "  # Generate primers from alignment"
echo "  generate_primers_denovo.py -i aligned.fasta -o primers.txt"
echo ""
echo "  # Score primers against alignment for coverage"
echo "  analyze_primers.py -f aligned.fasta -P primers.txt -o primer_hits.txt"
echo ""

if command -v generate_primers_denovo.py &>/dev/null; then
    show "Primer Prospector is installed! Running demo..."
    generate_primers_denovo.py -i "$OUTDIR/mafft_aligned.fasta" -o "$OUTDIR/pp_primers.txt" 2>&1 | head -10
else
    warn "Primer Prospector not installed."
    echo "  Install: pip install primerprospector"
    echo "  Expected output:"
    echo "    - primers.txt — list of candidate primers with positions"
    echo "    - primer_hits.txt — coverage stats per primer across sequences"
    echo "    - Columns: primer_seq, num_hits, percent_coverage, avg_mismatches"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: PUPpy
# ─────────────────────────────────────────────────────────────────────────────
section "2g) PUPpy — Phylogeny-aware Unique Primer design"

show "INPUT: ResultDB.tsv (from genome annotation) + CDS directory"
echo "  PUPpy designs taxon-specific primers by comparing CDS sequences"
echo "  across related organisms to find unique regions."
echo ""
show "COMMANDS:"
echo "  # Step 1: Identify unique regions"
echo "  puppy unique -i cds_directory/ -o unique_regions/"
echo ""
echo "  # Step 2: Design primers from unique regions"
echo "  puppy primers -i unique_regions/ -o puppy_primers/"
echo ""

if command -v puppy &>/dev/null; then
    show "PUPpy is installed!"
    puppy --help 2>&1 | head -5
else
    warn "PUPpy not installed."
    echo "  Install: pip install puppy-primers"
    echo "  Expected output:"
    echo "    - Primer tables (TSV) with: primer_name, sequence, Tm, GC%, target_gene"
    echo "    - Coverage plots showing primer specificity across taxa"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: DegePrime
# ─────────────────────────────────────────────────────────────────────────────
section "2h) DegePrime — Degenerate primer design from alignments"

show "INPUT: Trimmed alignment FASTA (MSA, trimmed to conserved region)"
echo "  Slides a window across the alignment and finds degenerate primers"
echo "  that cover the maximum number of sequences."
echo ""
show "COMMANDS:"
echo "  # Step 1: Trim alignment to remove gappy columns"
echo "  TrimAlignment.pl -i aligned.fasta -o trimmed.fasta -min 0.9"
echo ""
echo "  # Step 2: Find degenerate primers"
echo "  DegePrime.pl -i trimmed.fasta -o degeprime_output.tsv -l 20 -d 12"
echo "  # -l = primer length, -d = max degeneracy"
echo ""

if [ -f "DegePrime.pl" ] || command -v DegePrime.pl &>/dev/null; then
    show "DegePrime found! Running demo..."
    DegePrime.pl -i "$OUTDIR/mafft_aligned.fasta" -o "$OUTDIR/degeprime_output.tsv" -l 20 -d 12 2>&1 | head -10
else
    warn "DegePrime not installed."
    echo "  Install: git clone https://github.com/EnvGen/DegePrime"
    echo "  Expected output: TSV file with columns:"
    echo "    position, primer_seq, degeneracy, coverage, matching_seqs"
    echo "  Each row = one window position along the alignment"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: HYDEN
# ─────────────────────────────────────────────────────────────────────────────
section "2i) HYDEN — Degenerate primer pair design"

show "INPUT: FASTA of DNA sequences + primer constraints"
echo "  HYDEN uses an entropy-based algorithm to design degenerate primer"
echo "  pairs that cover a diverse set of sequences."
echo ""
show "COMMAND:"
echo "  hyden sequences.fasta -len 20 -deg 256 -amp_min 100 -amp_max 300"
echo "  # -len = primer length, -deg = max degeneracy, -amp = amplicon range"
echo ""

if command -v hyden &>/dev/null; then
    show "HYDEN is installed! Running demo..."
    hyden "$FASTA" -len 20 -deg 256 -amp_min 100 -amp_max 300 2>&1 | head -20
else
    warn "HYDEN not installed."
    echo "  Install: download from http://acgt.cs.tau.ac.il/hyden/"
    echo "  Expected output: degenerate primer pairs printed to stdout:"
    echo "    Forward: ACGTNRYSWKM...  (IUPAC degenerate bases)"
    echo "    Reverse: TGCANYRSWMK..."
    echo "    Degeneracy: 128, Coverage: 98.5%"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Multi-stage tools (Stages 2–4 combined)
# ─────────────────────────────────────────────────────────────────────────────
section "2j) PrimalScheme — Tiling primer scheme for viral genomes (Stages 2–4)"

show "INPUT: FASTA file of reference genomes (1 primary + optional alternates)"
echo "  PrimalScheme designs overlapping amplicon tiling schemes for"
echo "  sequencing entire viral genomes (like ARTIC for SARS-CoV-2)."
echo ""
show "COMMAND:"
echo "  primalscheme multiplex -a 400 -o primalscheme_output/ reference.fasta"
echo "  # -a 400 = target amplicon size of 400bp"
echo ""

if command -v primalscheme &>/dev/null; then
    show "PrimalScheme is installed! Running demo..."
    primalscheme multiplex -a 400 -o "$OUTDIR/primalscheme_output/" "$FASTA" 2>&1 | head -20
    echo ""
    ls -la "$OUTDIR/primalscheme_output/" 2>/dev/null
else
    warn "PrimalScheme not installed."
    echo "  Install: pip install primalscheme"
    echo "  Expected output files:"
    echo "    - scheme.primer.bed    — BED file with primer positions + pool assignments"
    echo "    - scheme.primer.tsv    — TSV: name, seq, pool, length, Tm, GC%"
    echo "    - scheme.report.json   — JSON report with coverage and quality metrics"
    echo "    - work/                — intermediate candidate files"
fi

section "2k) varVAMP — Variable VirusAMPlicon primer design (Stages 2–4)"

show "INPUT: MSA alignment (from Stage 1)"
echo "  varVAMP designs tiling primer schemes while accounting for"
echo "  sequence variation in viral populations."
echo ""
show "COMMAND:"
echo "  varvamp tiled tool_outputs/mafft_aligned.fasta tool_outputs/varvamp_output"
echo ""

if command -v varvamp &>/dev/null; then
    show "varVAMP is installed! Running demo..."
    varvamp tiled "$OUTDIR/mafft_aligned.fasta" "$OUTDIR/varvamp_output" 2>&1 | head -20
else
    warn "varVAMP not installed."
    echo "  Install: pip install varvamp"
    echo "  Expected output:"
    echo "    - primers.bed      — primer positions in BED format"
    echo "    - primers.tsv      — primer details (seq, Tm, GC%, pool)"
    echo "    - amplicons.bed    — amplicon regions"
    echo "    - plots/           — coverage and quality plots"
fi

section "2l) NGS-PrimerPlex — Multiplex panel design for NGS (Stages 2–4)"

show "INPUT: BED file of target regions + reference genome FASTA"
echo "  Designs multiplex primer panels for targeted NGS, optimizing"
echo "  primer compatibility and minimizing primer-dimers."
echo ""
show "COMMANDS:"
echo "  # Design primers for target regions"
echo "  ngs-primerplex -regions targets.bed -ref genome.fasta -o npp_output/"
echo ""
echo "  # Check primer interactions"
echo "  ngs-primerplex-check -primers npp_output/primers.tsv"
echo ""

if command -v ngs-primerplex &>/dev/null || python3 -c "import NGS_primerplex" 2>/dev/null; then
    show "NGS-PrimerPlex is installed!"
    echo "  (Requires BED + reference genome — skipping live demo)"
else
    warn "NGS-PrimerPlex not installed."
    echo "  Install: GitHub/Docker installation required (not available via pip in this environment)"
    echo "  Expected output:"
    echo "    - primers/info files for multiplex primer panel design"
    echo "    - reports for coverage / primer compatibility"
    echo "    - draft primers grouped into compatible pools"
fi

echo ""
show "STAGE 2 SUMMARY:"
echo "  primer3_core:       Boulder-IO text in  → Boulder-IO text out"
echo "  primer3-py:         Python dict in      → Python dict out"
echo "  eprimer3:           FASTA in            → tabular report out"
echo "  PMPrimer:           Multi-FASTA in      → primer design/evaluation result tables"
echo "  primerdiffer:       Two FASTAs in       → discriminatory primer TSV"
echo "  Primer Prospector:  Aligned FASTA in    → primer lists + coverage"
echo "  PUPpy:              CDS directory in    → primer tables + plots"
echo "  DegePrime:          Trimmed MSA in      → TSV degenerate windows"
echo "  HYDEN:              FASTA + constraints  → degenerate primer pairs"
echo "  PrimalScheme:       Reference FASTA in  → BED/TSV tiling scheme"
echo "  varVAMP:            MSA alignment in    → BED/TSV tiling scheme"
echo "  NGS-PrimerPlex:     BED + ref genome    → multiplex primer design reports/files"
echo "  Most Stage 2 tools produce: primer sequences, positions, Tm, GC%, and candidate-pair metadata"
}

###############################################################################
# STAGE 3: FILTERING / SPECIFICITY / IN-SILICO PCR
###############################################################################
stage3() {
banner "STAGE 3 — FILTERING / SPECIFICITY"

# Auto-consume Stage 2 output: parse PRIMER_LEFT_0 / PRIMER_RIGHT_0 from primer3_output.txt
P3_OUT="$OUTDIR/primer3_output.txt"
LEFT_PRIMER=""
RIGHT_PRIMER=""
if [ -f "$P3_OUT" ]; then
    LEFT_PRIMER=$(grep '^PRIMER_LEFT_0_SEQUENCE=' "$P3_OUT" | cut -d= -f2)
    RIGHT_PRIMER=$(grep '^PRIMER_RIGHT_0_SEQUENCE=' "$P3_OUT" | cut -d= -f2)
fi
# Fall back to hardcoded example if file absent or sequence not found
LEFT_PRIMER="${LEFT_PRIMER:-ACAAGCCTCACTCCCCTTAG}"
RIGHT_PRIMER="${RIGHT_PRIMER:-GGCATTTCCAGCAAAGCAGT}"

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: BLAST+ makeblastdb
# ─────────────────────────────────────────────────────────────────────────────
section "3a) BLAST+ makeblastdb — Create a searchable database"

show "INPUT: FASTA file of reference sequences"
show "COMMAND:"
echo "  makeblastdb -in $FASTA -dbtype nucl -out $OUTDIR/blastdb/sars2 -parse_seqids"

if command -v makeblastdb &>/dev/null; then
    mkdir -p "$OUTDIR/blastdb"
    makeblastdb -in "$FASTA" -dbtype nucl -out "$OUTDIR/blastdb/sars2" -parse_seqids > "$OUTDIR/makeblastdb_output.txt" 2>&1

    show "OUTPUT: Database files (.ndb, .nhr, .nin, .nsq, etc.)"
    ls -la "$OUTDIR/blastdb/"
    echo ""
    echo "Log:"
    cat "$OUTDIR/makeblastdb_output.txt"
else
    warn "BLAST+ not installed. Install: brew install blast (Mac) or sudo apt install ncbi-blast+ (Linux)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: BLAST+ blastn-short
# ─────────────────────────────────────────────────────────────────────────────
section "3b) BLAST+ blastn-short — Check primer specificity"

show "INPUT: Primer FASTA file + BLAST database"

cat > "$OUTDIR/primers_query.fasta" <<EOF
>left_primer
$LEFT_PRIMER
>right_primer
$RIGHT_PRIMER
EOF

echo "Primer query file ($OUTDIR/primers_query.fasta):"
cat "$OUTDIR/primers_query.fasta"

echo ""
show "COMMAND:"
echo "  blastn -task blastn-short -query $OUTDIR/primers_query.fasta \\"
echo "         -db $OUTDIR/blastdb/sars2 -evalue 1000 \\"
echo "         -word_size 7 -dust no -outfmt 6 \\"
echo "         -out $OUTDIR/blastn_short_output.txt"

if command -v blastn &>/dev/null && [ -f "$OUTDIR/blastdb/sars2.nsq" ]; then
    blastn -task blastn-short \
           -query "$OUTDIR/primers_query.fasta" \
           -db "$OUTDIR/blastdb/sars2" \
           -evalue 1000 \
           -word_size 7 \
           -dust no \
           -soft_masking false \
           -outfmt 6 \
           -out "$OUTDIR/blastn_short_output.txt" 2>/dev/null

    show "OUTPUT: Tab-separated hit table (outfmt 6)"
    echo "Columns: qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore"
    echo ""
    cat "$OUTDIR/blastn_short_output.txt"
    echo ""
    echo "Hits found: $(wc -l < "$OUTDIR/blastn_short_output.txt")"
    echo ""

    # Also show verbose output format
    show "BONUS — Human-readable format (outfmt 0):"
    echo "  blastn -task blastn-short -query primers -db sars2 -outfmt 0"
    blastn -task blastn-short \
           -query "$OUTDIR/primers_query.fasta" \
           -db "$OUTDIR/blastdb/sars2" \
           -evalue 1000 \
           -word_size 7 \
           -dust no \
           -outfmt 0 2>/dev/null | head -40
    echo "..."
else
    warn "BLAST+ not available or database not built."
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: MFEprimer
# ─────────────────────────────────────────────────────────────────────────────
section "3c) MFEprimer — Thermodynamics-aware primer QC"

show "INPUT:  Primer FASTA + indexed genome database"
show "COMMANDS:"
echo "  Step 1: mfeprimer index -i genome.fasta"
echo "  Step 2: mfeprimer spec  -i primers.fasta -d genome.fasta"
echo ""

if command -v mfeprimer &>/dev/null; then
    mfeprimer index -i "$FASTA" 2>/dev/null
    mfeprimer spec -i "$OUTDIR/primers_query.fasta" -d "$FASTA" > "$OUTDIR/mfeprimer_output.txt" 2>/dev/null

    show "OUTPUT: QC report with Tm, ΔG, binding counts"
    cat "$OUTDIR/mfeprimer_output.txt" | head -40
else
    warn "MFEprimer not installed. Get it from: https://github.com/quwubin/MFEprimer-3.0"
    echo "  Expected output: table with columns for each primer's Tm, GC%, hairpin ΔG,"
    echo "  dimer ΔG, and number of binding sites in the database."
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: isPcr (UCSC)
# ─────────────────────────────────────────────────────────────────────────────
section "3d) UCSC isPcr — In-silico PCR"

show "INPUT: Genome .2bit file + primer pair file (tab-separated: name, fwd, rev)"

cat > "$OUTDIR/ispcr_primers.txt" <<EOF
pair1	$LEFT_PRIMER	$RIGHT_PRIMER
EOF
echo "Primer file ($OUTDIR/ispcr_primers.txt):"
cat "$OUTDIR/ispcr_primers.txt"

echo ""
show "COMMANDS:"
echo "  faToTwoBit genome.fasta genome.2bit"
echo "  isPcr genome.2bit primers.txt output.txt"

if command -v isPcr &>/dev/null; then
    faToTwoBit "$FASTA" "$OUTDIR/genome.2bit" 2>/dev/null
    isPcr "$OUTDIR/genome.2bit" "$OUTDIR/ispcr_primers.txt" "$OUTDIR/ispcr_output.txt" 2>/dev/null

    show "OUTPUT: Predicted PCR products (FASTA-like format with coordinates)"
    cat "$OUTDIR/ispcr_output.txt"
else
    warn "isPcr not installed. Get it from: https://hgdownload.soe.ucsc.edu/admin/exe/"
    echo "  Expected output: FASTA of amplicon sequences with genomic coordinates."
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: Exonerate ipcress
# ─────────────────────────────────────────────────────────────────────────────
section "3e) Exonerate ipcress — In-silico PCR (mismatch tolerant)"

show "INPUT: Primer file (ipcress format) + FASTA sequences"

cat > "$OUTDIR/ipcress_primers.txt" <<EOF
pair1 $LEFT_PRIMER $RIGHT_PRIMER 100 300
EOF
echo "Primer file ($OUTDIR/ipcress_primers.txt):"
echo "Format: name  forward_seq  reverse_seq  min_product  max_product"
cat "$OUTDIR/ipcress_primers.txt"

echo ""
show "COMMAND:"
echo "  ipcress $OUTDIR/ipcress_primers.txt $FASTA --mismatch 1"

if command -v ipcress &>/dev/null; then
    ipcress "$OUTDIR/ipcress_primers.txt" "$FASTA" --mismatch 1 > "$OUTDIR/ipcress_output.txt" 2>/dev/null

    show "OUTPUT: Amplimer report (hit position, orientation, product size)"
    cat "$OUTDIR/ipcress_output.txt"
else
    warn "ipcress not installed. Install: sudo apt install exonerate"
    echo "  Expected output: hit reports showing sequence ID, primer positions,"
    echo "  product size, and number of mismatches."
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: EMBOSS primersearch
# ─────────────────────────────────────────────────────────────────────────────
section "3f) EMBOSS primersearch — Simple mismatch-tolerant PCR simulation"

show "INPUT: Primer pairs file + FASTA sequences"

cat > "$OUTDIR/primersearch_primers.txt" <<EOF
pair1 $LEFT_PRIMER $RIGHT_PRIMER
EOF
echo "Primer file ($OUTDIR/primersearch_primers.txt):"
cat "$OUTDIR/primersearch_primers.txt"

echo ""
show "COMMAND:"
echo "  primersearch -seqall $FASTA -infile $OUTDIR/primersearch_primers.txt -mismatchpercent 10 -outfile $OUTDIR/primersearch_output.txt"

if command -v primersearch &>/dev/null; then
    primersearch -seqall "$FASTA" -infile "$OUTDIR/primersearch_primers.txt" -mismatchpercent 10 -outfile "$OUTDIR/primersearch_output.txt" 2>/dev/null

    show "OUTPUT: Amplimer report per sequence"
    cat "$OUTDIR/primersearch_output.txt"
else
    warn "primersearch not installed. Install EMBOSS: brew install emboss (Mac) or sudo apt install emboss (Linux)"
    echo "  Expected output: for each sequence, shows primer name, amplimer length,"
    echo "  and positions of forward/reverse primer matches."
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: tntblast (LANL)
# ─────────────────────────────────────────────────────────────────────────────
section "3g) tntblast — Thermodynamic primer/probe matching"

show "INPUT: Assay definition file + target database (FASTA or BLAST DB)"
echo "  tntblast uses thermodynamic models (not just sequence matching) to"
echo "  predict whether primers will actually bind and amplify."
echo ""

cat > "$OUTDIR/tntblast_assay.txt" <<EOF
#name	forward	reverse
pair1	$LEFT_PRIMER	$RIGHT_PRIMER
EOF
echo "Assay file ($OUTDIR/tntblast_assay.txt):"
cat "$OUTDIR/tntblast_assay.txt"

echo ""
show "COMMAND:"
echo "  tntblast -i $OUTDIR/tntblast_assay.txt -d $FASTA -o $OUTDIR/tntblast_output.txt -e 45"
echo "  # -e 45 = minimum Tm threshold (°C)"
echo ""

if command -v tntblast &>/dev/null; then
    show "tntblast is installed! Running demo..."
    tntblast -i "$OUTDIR/tntblast_assay.txt" -d "$FASTA" -o "$OUTDIR/tntblast_output.txt" -e 45 2>&1 | head -30
    echo ""
    show "OUTPUT:"
    head -30 "$OUTDIR/tntblast_output.txt" 2>/dev/null
else
    warn "tntblast not installed."
    echo "  Install: download from https://public.lanl.gov/jgans/tntblast/"
    echo "  Expected output: tab-separated report with columns:"
    echo "    assay_name, target_id, fwd_Tm, rev_Tm, probe_Tm, amplicon_start,"
    echo "    amplicon_end, amplicon_length, fwd_mismatches, rev_mismatches"
    echo "  Key difference from BLAST: uses ΔG and Tm instead of just alignment score"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: VirtualPCR
# ─────────────────────────────────────────────────────────────────────────────
section "3h) VirtualPCR — Config-based in-silico PCR simulation"

show "INPUT: Configuration file + FASTA reference sequences"
echo "  VirtualPCR reads primer pairs from a config file and simulates"
echo "  PCR amplification against reference sequences."
echo ""
show "COMMAND:"
echo "  virtualpcr -config vpcr_config.txt -seq reference.fasta -out vpcr_output.txt"
echo ""

if command -v virtualpcr &>/dev/null; then
    show "VirtualPCR is installed! Running demo..."
    echo "  (Would need a config file — skipping live demo)"
else
    warn "VirtualPCR not installed."
    echo "  Install: see https://github.com/Shenglai/VirtualPCR or similar"
    echo "  Expected output: PCR product predictions including:"
    echo "    - target sequence ID, amplicon start/end, product size"
    echo "    - primer binding positions, mismatch count"
    echo "    - predicted amplicon sequence (optional)"
fi

echo ""
show "STAGE 3 SUMMARY:"
echo "  makeblastdb:    FASTA → binary database files (.ndb .nhr .nin .nsq)"
echo "  blastn-short:   primer FASTA + DB → tab-separated hit table"
echo "  MFEprimer:      primer FASTA + DB → QC report (Tm, ΔG, binding sites)"
echo "  tntblast:       assay file + DB → thermodynamic match report"
echo "  isPcr:          .2bit genome + primer TSV → amplicon FASTA + coordinates"
echo "  ipcress:        primer file + FASTA → amplimer hit report"
echo "  primersearch:   primer file + FASTA → amplimer report with mismatches"
echo "  VirtualPCR:     config + FASTA → PCR product predictions"
echo "  All answer: 'where does my primer bind, and how specifically?'"
}

###############################################################################
# STAGE 4: ASSAY SET OPTIMIZATION
###############################################################################
stage4() {
banner "STAGE 4 — ASSAY SET OPTIMIZATION"

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: Greedy Ranker (our pipeline's stage4_optimize.py)
# ─────────────────────────────────────────────────────────────────────────────
section "4a) Greedy Ranker — Simple score-based selection (our pipeline)"

show "INPUT: BLAST outfmt6 + ipcress/primersearch hits from Stage 3 → scored_pairs.json"

# Write the scoring adapter (converts Stage 3 tool outputs → scored_pairs.json)
cat > "$OUTDIR/scoring_adapter.py" <<'PYEOF'
#!/usr/bin/env python3
"""
scoring_adapter.py – Stage 3→4 bridge

Converts:
  - Primer3 Boulder-IO output   (primer3_output.txt)       → pair metadata
  - BLAST outfmt6 output        (blastn_short_output.txt)  → off-target hit counts
  - ipcress stdout              (ipcress_output.txt)       → amplimer hit counts
  - EMBOSS primersearch output  (primersearch_output.txt)  → amplimer hit counts

Into:
  - scored_pairs.json with explicit features + reproducible final_score

Usage:
  python3 scoring_adapter.py \
      --primer3      tool_outputs/primer3_output.txt \
      --blast        tool_outputs/blastn_short_output.txt \
      --ipcress      tool_outputs/ipcress_output.txt \
      --primersearch tool_outputs/primersearch_output.txt \
      --out          tool_outputs/stage4_scored_pairs.json
"""

import argparse, json, re
from pathlib import Path

# ---------------------------------------------------------------------------
# Scoring weights — all explicit so the formula is fully reproducible
# ---------------------------------------------------------------------------
OFF_TARGET_PEN_PER_HIT = 3.0   # per significant BLAST off-target (aln >= BLAST_MIN_ALN)
AMPLIMER_PEN_PER_HIT   = 5.0   # per non-specific amplimer from ipcress/primersearch
TM_PEN_WEIGHT          = 2.0   # per °C Tm mismatch between left and right primer
BLAST_MIN_ALN          = 15    # alignments shorter than this are noise; ignored


def final_score(blast_off: int, amplimer_off: int, tm_diff: float) -> float:
    """
    score = 100
          - blast_off    * OFF_TARGET_PEN_PER_HIT
          - amplimer_off * AMPLIMER_PEN_PER_HIT
          - tm_diff      * TM_PEN_WEIGHT
    Clamped to [0, 100].
    """
    return round(max(0.0,
        100.0
        - blast_off    * OFF_TARGET_PEN_PER_HIT
        - amplimer_off * AMPLIMER_PEN_PER_HIT
        - tm_diff      * TM_PEN_WEIGHT
    ), 2)


def parse_primer3(path):
    kv = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if "=" in line and not line.startswith("="):
                k, v = line.split("=", 1)
                kv[k] = v
    n = int(kv.get("PRIMER_PAIR_NUM_RETURNED", 0))
    pairs = []
    for i in range(n):
        lseq = kv.get(f"PRIMER_LEFT_{i}_SEQUENCE", "")
        rseq = kv.get(f"PRIMER_RIGHT_{i}_SEQUENCE", "")
        if not lseq or not rseq:
            continue
        ltm = float(kv.get(f"PRIMER_LEFT_{i}_TM", 0))
        rtm = float(kv.get(f"PRIMER_RIGHT_{i}_TM", 0))
        pairs.append({
            "pair_index":    i,
            "pair_id":       f"P_{i+1:03d}",
            "left_sequence": lseq,
            "right_sequence": rseq,
            "left_tm":       ltm,
            "right_tm":      rtm,
            "tm_diff":       round(abs(ltm - rtm), 2),
            "amplicon_size": int(kv.get(f"PRIMER_PAIR_{i}_PRODUCT_SIZE", 0)),
        })
    return pairs


def parse_blast(path):
    """
    Count significant BLAST hits per query name (aln >= BLAST_MIN_ALN), then
    subtract 1 for the expected on-target self-hit.

    NOTE: When the BLAST database contains multiple copies of the target genome
    (e.g. 5 SARS-CoV-2 strains), correct primers will appear to have N-1 extra
    hits for the same intended locus.  blast_off_target here means
    "significant matches beyond one assumed main hit", not true biological
    off-targets.  Use a single-genome DB or filter by subject ID for stricter
    specificity assessment.
    """
    counts = {}
    if not path or not Path(path).exists():
        return counts
    with open(path) as fh:
        for line in fh:
            cols = line.strip().split("\t")
            if len(cols) < 4:
                continue
            if int(cols[3]) >= BLAST_MIN_ALN:
                counts[cols[0]] = counts.get(cols[0], 0) + 1
    return {k: max(0, v - 1) for k, v in counts.items()}


def parse_ipcress(path):
    """
    Count amplimer hits per assay name from ipcress stdout.

    ipcress emits one line per amplimer product:
      ipcress: <assay_name> <seq_id> <product_len> A <pos> <mm> B <pos> <mm> pair
    Lines starting with '--' are status messages (not hits).
    Returns {} when the file is absent or contains no amplimer lines.
    """
    counts = {}
    if not path or not Path(path).exists():
        return counts
    with open(path) as fh:
        for line in fh:
            if line.startswith("ipcress:"):
                # Format: ipcress: <seq_id> <assay_name> <product_len> ...
                parts = line.split()
                if len(parts) >= 3:
                    counts[parts[2]] = counts.get(parts[2], 0) + 1
    return counts


def parse_primersearch(path):
    """
    Count amplimer hits per primer name from EMBOSS primersearch output.

    primersearch emits a block per primer set:
      Primer name <name>
      Amplimer 1
          Sequence: <seqid>
          ...
    Returns {} when the file is absent or no Amplimer blocks are present.
    """
    counts = {}
    if not path or not Path(path).exists():
        return counts
    current = None
    with open(path) as fh:
        for line in fh:
            m = re.match(r"Primer name\s+(\S+)", line)
            if m:
                current = m.group(1)
            elif current and re.match(r"\s*Amplimer \d+", line):
                counts[current] = counts.get(current, 0) + 1
    return counts


def build_scored_pairs(primer3, blast, ipcress, primersearch):
    pairs      = parse_primer3(primer3)
    blast_hits = parse_blast(blast)
    # merge ipcress + primersearch amplimer counts into one dict
    amp_hits   = parse_ipcress(ipcress)
    for k, v in parse_primersearch(primersearch).items():
        amp_hits[k] = amp_hits.get(k, 0) + v

    scored = []
    for p in pairs:
        i = p["pair_index"]
        # BLAST query name: try indexed form first, fall back to bare form for pair 0
        lkey = f"left_primer_{i}"  if f"left_primer_{i}"  in blast_hits else \
               ("left_primer"      if i == 0                             else None)
        rkey = f"right_primer_{i}" if f"right_primer_{i}" in blast_hits else \
               ("right_primer"     if i == 0                             else None)
        blast_off = (blast_hits.get(lkey, 0) + blast_hits.get(rkey, 0)) \
                    if (lkey and rkey) else 0

        # ipcress/primersearch assay names are 1-indexed: pair1 = P_001 (i=0), etc.
        amplimer_off = amp_hits.get(f"pair{i+1}", 0)

        score = final_score(blast_off, amplimer_off, p["tm_diff"])
        scored.append({
            "pair_id":            p["pair_id"],
            "left_sequence":      p["left_sequence"],
            "right_sequence":     p["right_sequence"],
            "amplicon_size":      p["amplicon_size"],
            "left_tm":            p["left_tm"],
            "right_tm":           p["right_tm"],
            "tm_diff":            p["tm_diff"],
            "blast_off_target":   blast_off,
            "amplimer_hits":      amplimer_off,
            "off_target_penalty": round(blast_off    * OFF_TARGET_PEN_PER_HIT, 2),
            "amplimer_penalty":   round(amplimer_off * AMPLIMER_PEN_PER_HIT,   2),
            "tm_penalty":         round(p["tm_diff"] * TM_PEN_WEIGHT,           2),
            "final_score":        score,
        })
    return sorted(scored, key=lambda x: x["final_score"], reverse=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--primer3",      required=True)
    ap.add_argument("--blast",        default=None)
    ap.add_argument("--ipcress",      default=None)
    ap.add_argument("--primersearch", default=None)
    ap.add_argument("--out",          required=True)
    args = ap.parse_args()

    scored = build_scored_pairs(args.primer3, args.blast, args.ipcress, args.primersearch)
    Path(args.out).write_text(json.dumps(scored, indent=2) + "\n")
    print(f"Wrote {len(scored)} scored pairs → {args.out}")
    for p in scored:
        print(f"  {p['pair_id']}  score={p['final_score']}  "
              f"amp={p['amplicon_size']}bp  "
              f"blast_off={p['blast_off_target']}  amplimers={p['amplimer_hits']}  "
              f"tm_diff={p['tm_diff']}")

if __name__ == "__main__":
    main()
PYEOF

show "COMMAND: (scoring adapter — auto-consumes Stage 3 outputs)"
echo "  python3 $OUTDIR/scoring_adapter.py \\"
echo "      --primer3      $OUTDIR/primer3_output.txt \\"
echo "      --blast        $OUTDIR/blastn_short_output.txt \\"
echo "      --ipcress      $OUTDIR/ipcress_output.txt \\"
echo "      --primersearch $OUTDIR/primersearch_output.txt \\"
echo "      --out          $OUTDIR/stage4_scored_pairs.json"
echo ""

# Run adapter if primer3 output is present; otherwise fall back to example data
if [ -f "$OUTDIR/primer3_output.txt" ]; then
    python3 "$OUTDIR/scoring_adapter.py" \
        --primer3      "$OUTDIR/primer3_output.txt" \
        --blast        "$OUTDIR/blastn_short_output.txt" \
        --ipcress      "$OUTDIR/ipcress_output.txt" \
        --primersearch "$OUTDIR/primersearch_output.txt" \
        --out          "$OUTDIR/stage4_scored_pairs.json" \
    || warn "  scoring_adapter.py failed; check Python 3 is available"
else
    warn "primer3_output.txt not found — writing example scored_pairs.json (run stage2 first)"
    cat > "$OUTDIR/stage4_scored_pairs.json" <<'JSONEOF'
[
  {"pair_id": "P_001", "left_sequence": "TCGAACTGCACCTCATGGTC", "right_sequence": "GACTTTAGATCGGCGCCGTA", "amplicon_size": 198, "tm_diff": 0.07, "blast_off_target": 0, "amplimer_hits": 0, "final_score": 99.86},
  {"pair_id": "P_002", "left_sequence": "TGTCGTTGACAGGACACGAG", "right_sequence": "AGTCTCCAAAGCCACGTACG", "amplicon_size": 218, "tm_diff": 0.07, "blast_off_target": 0, "amplimer_hits": 0, "final_score": 99.86},
  {"pair_id": "P_003", "left_sequence": "TCAAACGTTCGGATGCTCGA", "right_sequence": "GACTTTAGATCGGCGCCGTA", "amplicon_size": 214, "tm_diff": 0.07, "blast_off_target": 0, "amplimer_hits": 0, "final_score": 99.86},
  {"pair_id": "P_004", "left_sequence": "ACAAGCCTCACTCCCCTTAG", "right_sequence": "GGCATTTCCAGCAAAGCAGT", "amplicon_size": 290, "tm_diff": 0.50, "blast_off_target": 0, "amplimer_hits": 0, "final_score": 99.00},
  {"pair_id": "P_005", "left_sequence": "TGTACGTGCATGGATCAGGT", "right_sequence": "CAGGCGGTGGTTTAGACTAG", "amplicon_size": 182, "tm_diff": 0.30, "blast_off_target": 0, "amplimer_hits": 0, "final_score": 99.40}
]
JSONEOF
fi

echo "File: $OUTDIR/stage4_scored_pairs.json"
echo "Contents (5 scored pairs):"
python3 -c "
import json
with open('$OUTDIR/stage4_scored_pairs.json') as f:
    pairs = json.load(f)
for p in pairs:
    print(f\"  {p['pair_id']}  score={p['final_score']}  amp={p['amplicon_size']}bp  L={p['left_sequence'][:15]}...  R={p['right_sequence'][:15]}...\")
"

echo ""
show "ALGORITHM: Sort by final_score descending, greedily pick top pairs that don't reuse any primer sequence."
echo ""

# Run the greedy selection
cat > "$OUTDIR/greedy_ranker.py" <<'PYEOF'
#!/usr/bin/env python3
"""
Greedy primer pair selector (Stage 4 of our pipeline).

INPUT:  JSON array of scored primer pairs
OUTPUT: JSON array of top non-conflicting pairs
"""
import json, sys

input_path = sys.argv[1]
max_pairs = int(sys.argv[2]) if len(sys.argv) > 2 else 3

with open(input_path) as f:
    pairs = json.load(f)

# Sort by final_score descending
pairs.sort(key=lambda p: p["final_score"], reverse=True)

selected = []
used_seqs = set()

for p in pairs:
    if len(selected) >= max_pairs:
        break
    # Skip if either primer sequence already used
    if p["left_sequence"] in used_seqs or p["right_sequence"] in used_seqs:
        print(f"  SKIP {p['pair_id']} — primer sequence already used")
        continue
    selected.append(p)
    used_seqs.add(p["left_sequence"])
    used_seqs.add(p["right_sequence"])
    print(f"  SELECT {p['pair_id']}  score={p['final_score']}  amp={p['amplicon_size']}bp")

output_path = input_path.replace("scored_pairs", "final_panel")
with open(output_path, "w") as f:
    json.dump(selected, f, indent=2)
print(f"\nFinal panel ({len(selected)} pairs) saved to: {output_path}")
PYEOF

show "COMMAND:"
echo "  python3 $OUTDIR/greedy_ranker.py $OUTDIR/stage4_scored_pairs.json 3"
echo ""
show "OUTPUT: Top non-conflicting pairs selected:"

python3 "$OUTDIR/greedy_ranker.py" "$OUTDIR/stage4_scored_pairs.json" 3

echo ""
echo "Result file:"
cat "$OUTDIR/stage4_final_panel.json"

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: Olivar
# ─────────────────────────────────────────────────────────────────────────────
section "4b) Olivar — Tiling primer scheme design + SADDLE optimization"

show "Olivar combines Stages 2-4: it generates primers, checks specificity,"
echo "and optimizes the final tiling scheme using simulated annealing (SADDLE)."
echo ""

show "INPUT: Reference FASTA (or MSA) + optional BLAST database"
echo "  Olivar needs a reference genome to design tiling primers across."
echo ""

show "COMMANDS (two-step workflow):"
echo ""
echo "  Step 1 — Build a design database:"
echo "    olivar build -r reference.fasta -o olivar_db"
echo "    (optionally add: -b blastdb  for off-target filtering)"
echo ""
echo "  Step 2 — Design tiling primers:"
echo "    olivar tiling -d olivar_db -o olivar_output -t 400"
echo "    (-t 400 = target amplicon size of 400bp)"
echo ""

if command -v olivar &>/dev/null; then
    show "Olivar is installed! Running demo..."
    echo ""

    # Step 1: build
    show "Step 1: olivar build"
    echo "  olivar build -r $FASTA -o $OUTDIR/olivar_db"
    olivar build -r "$FASTA" -o "$OUTDIR/olivar_db" 2>&1 | head -20
    echo ""

    # Step 2: tiling
    show "Step 2: olivar tiling"
    echo "  olivar tiling -d $OUTDIR/olivar_db -o $OUTDIR/olivar_output -t 400"
    olivar tiling -d "$OUTDIR/olivar_db" -o "$OUTDIR/olivar_output" -t 400 2>&1 | head -20
    echo ""

    show "OUTPUT files:"
    ls -la "$OUTDIR/olivar_output"* 2>/dev/null || echo "  (check $OUTDIR/olivar_output/ for results)"
    echo ""
    echo "Expected output files:"
    echo "  - primer.bed       — primer positions in BED format"
    echo "  - primer.tsv       — primer sequences, Tm, GC%, pool assignments"
    echo "  - amplicon.bed     — amplicon regions"
    echo "  - config.json      — parameters used"
else
    warn "Olivar not installed."
    echo ""
    echo "  Install with:  pip install olivar"
    echo ""
    echo "  Expected outputs after 'olivar tiling':"
    echo "    primer.bed     — BED file with primer coordinates (chrom, start, end, name, pool)"
    echo "    primer.tsv     — TSV with columns: name, seq, length, Tm, GC%, pool"
    echo "    amplicon.bed   — BED file of amplicon regions"
    echo "    config.json    — run parameters"
    echo ""
    echo "  Olivar uses SADDLE (Simulated Annealing for Dimer Detection and"
    echo "  Localized Exclusion) to optimize primer pool assignments and"
    echo "  minimize primer-dimer interactions."
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: multiPrime
# ─────────────────────────────────────────────────────────────────────────────
section "4c) multiPrime — Minimal primer set via Snakemake pipeline"

show "INPUT: Config YAML + FASTA sequences (Snakemake workflow)"
echo "  multiPrime uses a Snakemake pipeline to design minimal sets of"
echo "  degenerate primers that cover diverse viral populations."
echo ""
show "COMMANDS:"
echo "  # Edit config.yaml with paths and parameters"
echo "  snakemake --snakefile multiPrime.smk --configfile config.yaml -j 4"
echo ""

if command -v snakemake &>/dev/null && [ -f "multiPrime.smk" ]; then
    show "multiPrime Snakemake file found!"
    echo "  (Full pipeline run requires config — skipping live demo)"
else
    warn "multiPrime not installed."
    echo "  Install: git clone https://github.com/quwubin/multiPrime"
    echo "  Requires: Snakemake, BLAST+, MAFFT, Primer3"
    echo "  Expected output:"
    echo "    - minimal_primers.tsv  — optimized primer sets"
    echo "    - coverage_report.txt  — coverage across input genomes"
    echo "    - Uses iterative set-cover to minimize total primers needed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: PrimalScheme3 (interaction checking / scheme repair)
# ─────────────────────────────────────────────────────────────────────────────
section "4d) PrimalScheme3 — Primer interaction checking & scheme repair"

show "INPUT: MSA + existing primer BED file"
echo "  PrimalScheme3 (v3) adds post-design optimization: it checks an"
echo "  existing primer scheme for dimer interactions and repairs problems"
echo "  by swapping in alternative primers."
echo ""
show "COMMANDS:"
echo "  # Check interactions in an existing scheme"
echo "  primalscheme3 check-interactions -b scheme.primer.bed -o interactions.tsv"
echo ""
echo "  # Repair scheme by replacing problematic primers"
echo "  primalscheme3 repair -b scheme.primer.bed -a aligned.fasta -o repaired/"
echo ""

if command -v primalscheme3 &>/dev/null; then
    show "PrimalScheme3 is installed!"
    primalscheme3 --help 2>&1 | head -10
else
    warn "PrimalScheme3 not installed."
    echo "  Install: pip install primalscheme3"
    echo "  Expected output:"
    echo "    - interactions.tsv     — pairwise dimer ΔG scores between primers"
    echo "    - repaired.primer.bed  — fixed BED with swapped primers"
    echo "    - repair_report.json   — what was changed and why"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TOOL: openPrimeR
# ─────────────────────────────────────────────────────────────────────────────
section "4e) openPrimeR — Set-cover optimized multiplex primer design (R)"

show "INPUT: Template sequences (FASTA) + candidate primer sets (CSV/FASTA)"
echo "  openPrimeR uses integer linear programming (ILP) / set-cover to"
echo "  find the minimum number of primers that cover all target templates."
echo "  Runs in R."
echo ""
show "COMMANDS (R):"
echo '  library(openPrimeR)'
echo '  templates <- read_templates("templates.fasta")'
echo '  primers   <- read_primers("candidates.fasta")'
echo '  # Optimize: find minimal covering set'
echo '  result <- optimize_primers(primers, templates, mode = "coverage")'
echo '  # Export results'
echo '  write_primers(result, "optimized_primers.csv")'
echo ""

if Rscript -e "library(openPrimeR)" 2>/dev/null; then
    show "openPrimeR is installed in R!"
    Rscript -e "library(openPrimeR); cat('Version:', as.character(packageVersion('openPrimeR')), '\n')" 2>/dev/null
else
    warn "openPrimeR not installed."
    echo "  Install in R: BiocManager::install('openPrimeR')"
    echo "  Expected output:"
    echo "    - optimized_primers.csv — minimal primer set with coverage stats"
    echo "    - Columns: primer_id, sequence, Tm, GC%, coverage_percent"
    echo "    - Also produces coverage plots and constraint evaluation reports"
    echo "    - Uses ILP solver to guarantee optimal (minimum) set size"
fi

echo ""
show "STAGE 4 SUMMARY:"
echo "  Greedy ranker:   scored pairs JSON → top N non-conflicting pairs JSON"
echo "  Olivar (SADDLE):  reference FASTA → tiling primer BED/TSV + amplicon BED"
echo "  multiPrime:       config YAML + FASTA → minimal degenerate primer sets"
echo "  PrimalScheme3:    BED + MSA → interaction reports + repaired scheme"
echo "  openPrimeR:       templates + candidates (R) → set-cover optimized sets"
echo "  All answer: 'which primers should I actually use in my assay?'"
}

###############################################################################
# IO SUMMARY — Clean table of what each tool takes in and puts out
###############################################################################
io_summary() {
banner "TOOL INPUT / OUTPUT SUMMARY"

echo -e "${BOLD}┌───────────────────────┬────────────────────────────────────────┬────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│ Tool                  │ Input                                  │ Output                                 │${NC}"
echo -e "${BOLD}├───────────────────────┼────────────────────────────────────────┼────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│ STAGE 1 — ALIGNMENT                                                                                    │${NC}"
echo -e "│ MAFFT                 │ Multi-FASTA (unaligned)                 │ Multi-FASTA (aligned, with '-' gaps)   │"
echo -e "│ Clustal Omega         │ Multi-FASTA (unaligned, 3+ seqs)       │ Multi-FASTA (aligned, with '-' gaps)   │"
echo -e "${BOLD}├───────────────────────┼────────────────────────────────────────┼────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│ STAGE 2 — CANDIDATE GENERATION                                                                         │${NC}"
echo -e "│ primer3_core          │ Boulder-IO text (key=value)             │ Boulder-IO text (seqs, Tm, GC%, pos)   │"
echo -e "│ primer3-py            │ Python dict                            │ Python dict (same fields)              │"
echo -e "│ eprimer3 (EMBOSS)     │ Single-seq FASTA                       │ Tabular primer report (text)           │"
echo -e "│ PMPrimer              │ FASTA (aligned or unaligned)           │ JSON/CSV primer sets                   │"
echo -e "│ primerdiffer          │ Two genomes FASTA + optional VCF       │ Discriminatory primer sets             │"
echo -e "│ Primer Prospector     │ Aligned FASTA                          │ Primer lists + coverage stats          │"
echo -e "│ PUPpy                 │ ResultDB.tsv + CDS directory           │ Primer tables + plots                  │"
echo -e "│ DegePrime             │ Trimmed alignment FASTA                │ TSV of degenerate primer windows       │"
echo -e "│ HYDEN                 │ DNA sequences + constraints            │ Degenerate primer pairs                │"
echo -e "${CYAN}│ STAGE 2–4 (multi-stage tools)                                                                          │${NC}"
echo -e "│ PrimalScheme          │ FASTA references (viral genomes)       │ Primer BED/TSV + JSON reports          │"
echo -e "│ Olivar                │ MSA or reference FASTA                 │ Primer BED + config files              │"
echo -e "│ varVAMP               │ MSA alignment                          │ Primer schemes                         │"
echo -e "│ NGS-PrimerPlex        │ BED + reference genome                 │ Multiplex primer panels                │"
echo -e "${BOLD}├───────────────────────┼────────────────────────────────────────┼────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│ STAGE 3 — SPECIFICITY / FILTERING / IN-SILICO PCR                                                      │${NC}"
echo -e "│ makeblastdb           │ FASTA reference                        │ Binary DB files (.ndb .nhr .nin etc)   │"
echo -e "│ blastn-short          │ Primer FASTA + BLAST DB                │ Tab-separated hit table (outfmt 6)     │"
echo -e "│ MFEprimer             │ Primer FASTA + indexed DB              │ QC report (Tm, ΔG, binding sites)      │"
echo -e "│ tntblast              │ Assay file + DB                        │ Thermodynamic match report             │"
echo -e "│ isPcr (UCSC)          │ .2bit genome + primer TSV              │ Amplicon FASTA + coordinates           │"
echo -e "│ ipcress (Exonerate)   │ Primer file + FASTA                    │ Amplimer hit report (text)             │"
echo -e "│ primersearch (EMBOSS) │ Primer pairs file + FASTA              │ Amplimer report with mismatches        │"
echo -e "│ VirtualPCR            │ Config file + FASTA                    │ PCR product predictions                │"
echo -e "${BOLD}├───────────────────────┼────────────────────────────────────────┼────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│ STAGE 4 — OPTIMIZATION / POOLING                                                                       │${NC}"
echo -e "│ Greedy ranker (ours)  │ Scored pairs JSON                      │ Top N non-conflicting pairs JSON       │"
echo -e "│ Olivar (SADDLE)       │ Reference FASTA (+ optional DB)        │ primer.bed, primer.tsv, amplicon.bed   │"
echo -e "│ multiPrime            │ Config YAML + FASTA (Snakemake)        │ Minimal primer sets                    │"
echo -e "│ PrimalScheme3         │ MSA + BED                              │ Interaction reports + scheme repair     │"
echo -e "│ openPrimeR            │ Template seqs + primer sets (R)        │ Set-cover optimized multiplex sets     │"
echo -e "${BOLD}├───────────────────────┼────────────────────────────────────────┼────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│ NON-CLI (Web/GUI only)                                                                                 │${NC}"
echo -e "│ Primer-BLAST          │ Template seq + BLAST DB (server)       │ Primer pairs + specificity alignments  │"
echo -e "│ Benchling             │ DNA sequence (UI)                      │ Primer candidates + CSV export         │"
echo -e "│ OligoArchitect        │ Input seq + assay parameters           │ Primer/probe designs (Excel export)    │"
echo -e "│ Primer Express        │ qPCR assay inputs (GUI)                │ Primers/probes                         │"
echo -e "│ PrimerQuest (IDT)     │ FASTA / accession / Excel upload       │ Primer pairs / qPCR assays             │"
echo -e "${BOLD}└───────────────────────┴────────────────────────────────────────┴────────────────────────────────────────┘${NC}"
echo ""
echo -e "${YELLOW}Key observations:${NC}"
echo "  • Stage 1 tools are swappable — both output aligned FASTA"
echo "  • Stage 2 tools all produce: primer sequence, position, Tm, GC%"
echo "  • Stage 3 tools all answer: where does my primer bind, and how specifically?"
echo "  • Stage 4 tools all answer: which primers should I actually use in my assay?"
echo "  • Multi-stage tools (PrimalScheme, Olivar, varVAMP, NGS-PrimerPlex) span Stages 2–4"
echo "  • Web-only tools (Primer-BLAST, Benchling, etc.) cannot be used in CLI pipelines"
echo ""
echo "  • JSON files connect the stages (candidates → scored pairs → final panel)"
echo "  • Any tool can be swapped as long as it reads/writes the same format"
}

###############################################################################
# MAIN
###############################################################################
STAGE="${1:-all}"

echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   PRIMER DESIGN TOOL EXPLORER                        ║${NC}"
echo -e "${BOLD}║   See exact inputs & outputs for each tool            ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Input FASTA: $FASTA ($(grep -c '^>' "$FASTA") sequences)"
echo "Output dir:  $OUTDIR/"
echo ""

case "$STAGE" in
    stage1) stage1 ;;
    stage2) stage2 ;;
    stage3) stage3 ;;
    stage4) stage4 ;;
    summary) io_summary ;;
    all)
        stage1
        stage2
        stage3
        stage4
        io_summary
        banner "ALL STAGES COMPLETE"
        echo "All input/output files are in: $OUTDIR/"
        echo ""
        echo "Files created:"
        ls -la "$OUTDIR/" 2>/dev/null
        ;;
    *) echo "Usage: $0 [stage1|stage2|stage3|stage4|summary|all]" ;;
esac
