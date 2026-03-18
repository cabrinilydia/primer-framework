#!/usr/bin/env python3
"""
run_pipeline.py – Run the full primer-design pipeline (stages 1–4).

Usage:
    python -m pipeline.run_pipeline -i input/test5.fasta
    python -m pipeline.run_pipeline -i input/test5.fasta -c configs/config.json
"""

import argparse, os, sys, time
from pipeline.utils import get_logger, load_json
from pipeline import stage1_align, stage2_generate, stage3_filter_score, stage4_optimize

log = get_logger()

DEFAULT_CONFIG = os.path.join("configs", "config.json")
WORK_DIR = "work"
OUTPUT_DIR = "output"


def main():
    parser = argparse.ArgumentParser(description="Universal primer design pipeline (MVP)")
    parser.add_argument("-i", "--input", required=True, help="Input FASTA file")
    parser.add_argument("-c", "--config", default=DEFAULT_CONFIG, help="Config JSON")
    parser.add_argument("--skip-blast", action="store_true",
                        help="Force-skip BLAST even if blast_db is set")
    args = parser.parse_args()

    if not os.path.isfile(args.input):
        log.error(f"Input file not found: {args.input}")
        sys.exit(1)

    config = load_json(args.config) if os.path.isfile(args.config) else {}
    if args.skip_blast:
        config["blast_db"] = ""

    t0 = time.time()
    log.info("=" * 60)
    log.info("PRIMER DESIGN PIPELINE – START")
    log.info("=" * 60)

    # Stage 1
    stage1_align.run(args.input, WORK_DIR, config)

    # Stage 2
    stage2_generate.run(WORK_DIR, config)

    # Stage 3
    stage3_filter_score.run(WORK_DIR, config)

    # Stage 4
    stage4_optimize.run(WORK_DIR, OUTPUT_DIR, config)

    elapsed = time.time() - t0
    log.info("=" * 60)
    log.info(f"PIPELINE COMPLETE in {elapsed:.1f}s")
    log.info(f"Results: {OUTPUT_DIR}/04_final_panel.json")
    log.info("=" * 60)


if __name__ == "__main__":
    main()
