"""
stage2_generate.py – Stage 2: Candidate generation + cheap prefiltering

Current implementation: primer3_core (Boulder-IO via subprocess)
TODO: swap to oligoTM, Primer-BLAST, or a custom sliding-window generator.
"""

import os, re, subprocess, hashlib
from pipeline.utils import (
    get_logger, save_json, read_fasta, consensus_from_alignment,
)

log = get_logger()

# ---------------------------------------------------------------------------
# Boulder-IO helpers
# ---------------------------------------------------------------------------

def _build_boulder_io(seq: str, config: dict) -> str:
    """Build Boulder-IO input string for primer3_core."""
    lines = [
        f"SEQUENCE_ID=consensus",
        f"SEQUENCE_TEMPLATE={seq}",
        f"PRIMER_TASK=generic",
        f"PRIMER_PICK_LEFT_PRIMER=1",
        f"PRIMER_PICK_RIGHT_PRIMER=1",
        f"PRIMER_NUM_RETURN={config.get('num_return', 50)}",
        f"PRIMER_MIN_SIZE={config.get('primer_min_size', 18)}",
        f"PRIMER_OPT_SIZE={config.get('primer_opt_size', 20)}",
        f"PRIMER_MAX_SIZE={config.get('primer_max_size', 25)}",
        f"PRIMER_MIN_TM={config.get('primer_min_tm', 57.0)}",
        f"PRIMER_OPT_TM={config.get('primer_opt_tm', 60.0)}",
        f"PRIMER_MAX_TM={config.get('primer_max_tm', 63.0)}",
        f"PRIMER_MIN_GC={config.get('primer_min_gc', 40.0)}",
        f"PRIMER_MAX_GC={config.get('primer_max_gc', 60.0)}",
        f"PRIMER_PRODUCT_SIZE_RANGE={config.get('product_size_min', 100)}-{config.get('product_size_max', 300)}",
        "=",  # Boulder-IO record terminator
    ]
    return "\n".join(lines) + "\n"


def _parse_primer3_output(raw: str) -> list[dict]:
    """Parse primer3_core stdout into a list of candidate dicts."""
    # Collect key=value pairs
    kv: dict[str, str] = {}
    for line in raw.strip().split("\n"):
        if "=" in line and not line.startswith("="):
            k, v = line.split("=", 1)
            kv[k] = v

    n_returned = int(kv.get("PRIMER_PAIR_NUM_RETURNED", 0))
    if n_returned == 0:
        log.warning("Primer3 returned 0 pairs.")
        return []

    candidates = []
    cid = 0
    for i in range(n_returned):
        for side, prefix_tag, strand in [("left", "LEFT", "+"), ("right", "RIGHT", "-")]:
            seq_key = f"PRIMER_{prefix_tag}_{i}_SEQUENCE"
            pos_key = f"PRIMER_{prefix_tag}_{i}"
            tm_key  = f"PRIMER_{prefix_tag}_{i}_TM"
            gc_key  = f"PRIMER_{prefix_tag}_{i}_GC_PERCENT"

            seq = kv.get(seq_key, "")
            if not seq:
                continue
            pos_str = kv.get(pos_key, "0,0")
            start, length = (int(x) for x in pos_str.split(","))

            cid += 1
            tag = "L" if side == "left" else "R"
            candidates.append({
                "candidate_id": f"{tag}_{cid:03d}",
                "sequence": seq,
                "start": start,
                "end": start + length - 1 if strand == "+" else start - length + 1,
                "strand": strand,
                "length": length,
                "gc_percent": float(kv.get(gc_key, 0)),
                "tm": float(kv.get(tm_key, 0)),
                "source_tool": "primer3",
                "pair_index": i,  # keep track so we can re-pair later
            })
    return candidates


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def run(work_dir: str, config: dict) -> str:
    """Generate primer candidates. Returns path to candidates JSON."""
    aligned_path = os.path.join(work_dir, "01_aligned.fasta")
    out_json = os.path.join(work_dir, "02_candidates.json")
    raw_path = os.path.join(work_dir, "02_primer3_raw.txt")

    # Build consensus sequence from alignment
    records = read_fasta(aligned_path)
    consensus = consensus_from_alignment(records)
    log.info(f"Stage 2: consensus length = {len(consensus)} bp")

    # Prepare Boulder-IO input
    boulder = _build_boulder_io(consensus, config)

    # Run primer3_core
    p3_exe = config.get("primer3_core_exe", "primer3_core")
    log.info(f"Running: echo <boulder> | {p3_exe}")
    try:
        result = subprocess.run(
            [p3_exe],
            input=boulder,
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        raise RuntimeError(
            f"primer3_core executable '{p3_exe}' not found. "
            "Install primer3 or update primer3_core_exe in config."
        )

    raw_out = result.stdout
    # Save raw output for debugging
    with open(raw_path, "w") as fh:
        fh.write(raw_out)
    log.info(f"Raw Primer3 output saved to {raw_path}")

    # Parse
    candidates = _parse_primer3_output(raw_out)
    log.info(f"Stage 2: {len(candidates)} candidate primers generated")

    save_json(candidates, out_json)
    log.info(f"Candidates saved to {out_json}")
    return out_json
