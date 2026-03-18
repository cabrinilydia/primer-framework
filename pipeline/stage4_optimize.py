"""
stage4_optimize.py – Stage 4: Assay-set optimization

Current implementation: greedy ranking by final_score, skip duplicates.
TODO: swap to set-cover, ILP, or multi-objective optimization.
"""

import os
from pipeline.utils import get_logger, load_json, save_json

log = get_logger()


def run(work_dir: str, output_dir: str, config: dict) -> str:
    """Select the final primer panel. Returns path to output JSON."""
    scored_path = os.path.join(work_dir, "03_scored_pairs.json")
    out_path = os.path.join(output_dir, "04_final_panel.json")
    os.makedirs(output_dir, exist_ok=True)

    pairs = load_json(scored_path)
    log.info(f"Stage 4: {len(pairs)} scored pairs loaded")

    # Sort by final_score descending
    pairs.sort(key=lambda p: p["final_score"], reverse=True)

    max_pairs = config.get("max_final_pairs", 5)
    selected = []
    used_seqs: set[str] = set()

    for p in pairs:
        if len(selected) >= max_pairs:
            break
        # Skip if either primer sequence already used (non-conflicting)
        if p["left_sequence"] in used_seqs or p["right_sequence"] in used_seqs:
            continue
        selected.append(p)
        used_seqs.add(p["left_sequence"])
        used_seqs.add(p["right_sequence"])

    log.info(f"Stage 4: selected {len(selected)} final pairs (max {max_pairs})")
    save_json(selected, out_path)
    log.info(f"Final panel saved to {out_path}")

    # Print summary
    for p in selected:
        log.info(
            f"  {p['pair_id']}  score={p['final_score']}  "
            f"amp={p['amplicon_size']}  L={p['left_sequence'][:15]}…  R={p['right_sequence'][:15]}…"
        )

    return out_path
