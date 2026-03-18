"""
stage3_filter_score.py – Stage 3: Expensive filtering / scoring

Current implementation: BLAST+ (blastn -task blastn-short) + simple thermo/pair filtering
TODO: swap BLAST for Bowtie2, BLAT, or thermodynamic off-target engine.
"""

import os, subprocess, tempfile, math
from pipeline.utils import get_logger, load_json, save_json

log = get_logger()

# ---------------------------------------------------------------------------
# BLAST helpers
# ---------------------------------------------------------------------------

def _blast_primer(seq: str, config: dict) -> int:
    """
    BLAST a single primer sequence; return number of off-target hits.
    Returns 0 if no BLAST DB is configured (skip specificity check).

    Only counts hits where alignment length >= blast_min_hit_length (default 15).
    Short partial matches (7-8bp) are random noise and should be ignored.
    """
    blast_db = config.get("blast_db", "")
    if not blast_db:
        return 0  # no DB → skip

    blastn = config.get("blastn_exe", "blastn")
    evalue = config.get("blast_evalue", 10)
    min_hit_len = config.get("blast_min_hit_length", 15)

    with tempfile.NamedTemporaryFile("w", suffix=".fa", delete=False) as tmp:
        tmp.write(f">query\n{seq}\n")
        tmp_path = tmp.name

    cmd = [
        blastn,
        "-task", "blastn-short",
        "-db", blast_db,
        "-query", tmp_path,
        "-evalue", str(evalue),
        "-outfmt", "6",  # tabular: qseqid sseqid pident length ...
        "-max_target_seqs", "50",
        "-num_threads", "2",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        # Parse tabular output — column 3 = alignment length
        significant_hits = 0
        for line in result.stdout.strip().split("\n"):
            if not line:
                continue
            cols = line.split("\t")
            if len(cols) >= 4:
                aln_len = int(cols[3])
                if aln_len >= min_hit_len:
                    significant_hits += 1
        # Subtract 1 for the expected self-hit (primer binding its own target)
        return max(0, significant_hits - 1)
    except FileNotFoundError:
        log.warning(f"blastn not found at '{blastn}'; skipping specificity check.")
        return 0
    except subprocess.CalledProcessError as exc:
        log.warning(f"BLAST failed: {exc.stderr[:200]}")
        return 0
    finally:
        os.unlink(tmp_path)


# ---------------------------------------------------------------------------
# Pairing and scoring
# ---------------------------------------------------------------------------

def _form_pairs(candidates: list[dict], config: dict) -> list[dict]:
    """
    Pair lefts and rights that came from the same primer3 pair_index,
    then filter and score.
    """
    # Group by pair_index
    lefts = {c["pair_index"]: c for c in candidates if c["candidate_id"].startswith("L")}
    rights = {c["pair_index"]: c for c in candidates if c["candidate_id"].startswith("R")}

    product_min = config.get("product_size_min", 100)
    product_max = config.get("product_size_max", 300)
    max_off = config.get("blast_max_off_targets", 5)
    off_target_pen = config.get("off_target_penalty_per_hit", 3.0)
    tm_pen_w = config.get("tm_diff_penalty_weight", 2.0)

    seen_seqs = set()
    pairs = []
    pid = 0

    for idx in sorted(set(lefts.keys()) & set(rights.keys())):
        left = lefts[idx]
        right = rights[idx]

        # Amplicon size (approximate from coordinates)
        amp_size = abs(right["start"] - left["start"]) + 1
        if not (product_min <= amp_size <= product_max):
            continue

        # Skip duplicate primer sequences
        pair_key = (left["sequence"], right["sequence"])
        if pair_key in seen_seqs:
            continue
        seen_seqs.add(pair_key)

        # Tm difference
        tm_diff = abs(left["tm"] - right["tm"])

        # BLAST specificity
        left_off = _blast_primer(left["sequence"], config)
        right_off = _blast_primer(right["sequence"], config)
        total_off = left_off + right_off

        if total_off > max_off * 2:
            log.debug(f"Pair {idx} skipped: {total_off} off-target hits")
            continue

        # Scoring: final_score = 100 - penalty - off_target_penalty - tm_diff_penalty
        penalty = 0.0  # placeholder for future heuristics
        off_pen = total_off * off_target_pen
        tm_pen = tm_diff * tm_pen_w
        final_score = round(100.0 - penalty - off_pen - tm_pen, 2)

        pid += 1
        pairs.append({
            "pair_id": f"P_{pid:03d}",
            "left_id": left["candidate_id"],
            "right_id": right["candidate_id"],
            "left_sequence": left["sequence"],
            "right_sequence": right["sequence"],
            "amplicon_size": amp_size,
            "tm_diff": round(tm_diff, 2),
            "off_target_hits": total_off,
            "specificity_score": round(1.0 - min(total_off / 20.0, 1.0), 2),
            "penalty_score": round(penalty, 2),
            "final_score": final_score,
        })

    return pairs


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def run(work_dir: str, config: dict) -> str:
    """Filter and score primer pairs. Returns path to scored-pairs JSON."""
    cand_path = os.path.join(work_dir, "02_candidates.json")
    out_path = os.path.join(work_dir, "03_scored_pairs.json")

    candidates = load_json(cand_path)
    log.info(f"Stage 3: loaded {len(candidates)} candidates")

    pairs = _form_pairs(candidates, config)
    log.info(f"Stage 3: {len(pairs)} scored pairs survive filtering")

    save_json(pairs, out_path)
    log.info(f"Scored pairs saved to {out_path}")
    return out_path