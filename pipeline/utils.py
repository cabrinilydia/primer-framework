"""
utils.py – shared helpers for the primer-design pipeline.
"""

import json, os, sys, logging

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

def get_logger(name: str = "primer-pipeline") -> logging.Logger:
    """Return a pre-configured logger."""
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(logging.Formatter(
            "%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S"
        ))
        logger.addHandler(handler)
        logger.setLevel(logging.DEBUG)
    return logger

# ---------------------------------------------------------------------------
# JSON I/O
# ---------------------------------------------------------------------------

def load_json(path: str):
    with open(path) as fh:
        return json.load(fh)

def save_json(obj, path: str):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as fh:
        json.dump(obj, fh, indent=2)

# ---------------------------------------------------------------------------
# FASTA helpers
# ---------------------------------------------------------------------------

def read_fasta(path: str) -> list[dict]:
    """Return list of {id, description, sequence} dicts."""
    records = []
    header, seq_parts = None, []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if header is not None:
                    records.append(_fasta_record(header, seq_parts))
                header = line[1:]
                seq_parts = []
            else:
                seq_parts.append(line)
    if header is not None:
        records.append(_fasta_record(header, seq_parts))
    return records

def _fasta_record(header: str, seq_parts: list[str]) -> dict:
    parts = header.split(None, 1)
    return {
        "id": parts[0],
        "description": parts[1] if len(parts) > 1 else "",
        "sequence": "".join(seq_parts),
    }

def write_fasta(records: list[dict], path: str):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as fh:
        for r in records:
            desc = f" {r['description']}" if r.get("description") else ""
            fh.write(f">{r['id']}{desc}\n")
            seq = r["sequence"]
            for i in range(0, len(seq), 80):
                fh.write(seq[i:i+80] + "\n")

# ---------------------------------------------------------------------------
# Consensus from aligned FASTA (majority-rule, gaps ignored)
# ---------------------------------------------------------------------------

def consensus_from_alignment(records: list[dict]) -> str:
    """Majority-rule consensus; gap characters ('-') are ignored."""
    if len(records) == 1:
        return records[0]["sequence"].replace("-", "")
    seqs = [r["sequence"] for r in records]
    length = max(len(s) for s in seqs)
    consensus = []
    for i in range(length):
        counts: dict[str, int] = {}
        for s in seqs:
            if i < len(s) and s[i] not in ("-", "N", "n"):
                counts[s[i].upper()] = counts.get(s[i].upper(), 0) + 1
        if counts:
            consensus.append(max(counts, key=counts.get))  # type: ignore
    return "".join(consensus)
