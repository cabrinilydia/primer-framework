"""
stage1_align.py – Stage 1: Input / Alignment

Current implementation: MAFFT
TODO: swap to MUSCLE, Clustal Omega, or any other MSA tool.
"""

import shutil, subprocess, os
from pipeline.utils import get_logger, load_json, save_json, read_fasta, write_fasta

log = get_logger()

def run(input_fasta: str, work_dir: str, config: dict) -> str:
    """
    Align input sequences (or pass through if only one).
    Returns path to aligned FASTA in work_dir.
    """
    out_fasta = os.path.join(work_dir, "01_aligned.fasta")
    meta_path = os.path.join(work_dir, "01_meta.json")
    os.makedirs(work_dir, exist_ok=True)

    records = read_fasta(input_fasta)
    n_seq = len(records)
    seq_ids = [r["id"] for r in records]
    log.info(f"Stage 1: {n_seq} sequence(s) found in {input_fasta}")

    if n_seq == 0:
        raise RuntimeError("Input FASTA contains no sequences.")

    if n_seq == 1:
        # Single sequence – no alignment needed
        log.info("Single sequence; copying as-is.")
        shutil.copy2(input_fasta, out_fasta)
    else:
        # Multiple sequences – run MAFFT
        mafft_exe = config.get("mafft_exe", "mafft")

        # Strategy selection:
        #   "fast"     → --retree 1          (FFT-NS-1, single iteration, fastest)
        #   "auto"     → --auto              (MAFFT picks best strategy for input size)
        #   "accurate" → --maxiterate 1000   (best accuracy, slowest)
        strategy = config.get("mafft_strategy", "auto")
        strategy_flags = {
            "fast":     ["--retree", "1"],
            "auto":     ["--auto"],
            "accurate": ["--maxiterate", "1000"],
        }
        if strategy not in strategy_flags:
            log.warning(f"Unknown mafft_strategy '{strategy}', falling back to 'auto'")
            strategy = "auto"

        cmd = [mafft_exe] + strategy_flags[strategy] + ["--thread", "-1", input_fasta]
        log.info(f"Running ({strategy} strategy): {' '.join(cmd)}")
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        except FileNotFoundError:
            raise RuntimeError(
                f"MAFFT executable '{mafft_exe}' not found. "
                "Install it or update mafft_exe in config."
            )
        with open(out_fasta, "w") as fh:
            fh.write(result.stdout)
        log.info(f"MAFFT alignment written to {out_fasta}")

    # Save metadata
    meta = {"n_sequences": n_seq, "sequence_ids": seq_ids}
    save_json(meta, meta_path)
    log.info(f"Metadata saved to {meta_path}")
    return out_fasta