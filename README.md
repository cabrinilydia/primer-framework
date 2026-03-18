# Primer Design Pipeline – MVP

A modular, four-stage universal primer design framework.

## Pipeline stages

| Stage | File |
|---|---|
| 1 – Align | `stage1_align.py` |
| 2 – Generate | `stage2_generate.py` |
| 3 – Filter/Score | `stage3_filter_score.py` |
| 4 – Optimize | `stage4_optimize.py` |

## Prerequisites

```bash
# macOS (Homebrew)
brew install mafft primer3 blast

# Ubuntu / Debian
sudo apt-get install mafft primer3 ncbi-blast+
```

## Quick start

```bash
# Copy your FASTA into input/
cp test5.fasta input/

# Run the full pipeline (no BLAST DB → specificity check skipped)
cd primer-framework
python -m pipeline.run_pipeline -i input/test5.fasta

# Run with a custom config
python -m pipeline.run_pipeline -i input/test5.fasta -c configs/config.json

# Explicitly skip BLAST
python -m pipeline.run_pipeline -i input/test5.fasta --skip-blast
```

## Output

- `work/01_aligned.fasta` – aligned sequences
- `work/02_candidates.json` – all primer candidates
- `work/03_scored_pairs.json` – filtered and scored pairs
- `output/04_final_panel.json` – top selected primer panel

## Configuration

Edit `configs/config.json` to set primer size ranges, Tm bounds, product size range, BLAST database path, executable paths, and the maximum number of final pairs.

## Architecture

Each stage reads JSON/FASTA from `work/`, processes it, and writes JSON/FASTA back. Stages communicate only through files — swap any stage by replacing its Python file.
