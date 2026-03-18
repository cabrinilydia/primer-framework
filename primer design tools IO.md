# Primer Design Tools


## Complete Tool I/O Summary (Working + Not Working + Not Installed)

| **Tool** | **Stage** | **Status in your environment** | **Exact Input File(s) / Input Type** | **Exact Output File(s) / Output Type** | **Actual or Expected Output Format / Fields** | **Consumed by Next Stage? / How used** |
|---|---:|---|---|---|---|---|
| **MAFFT** | 1 | Working | `test5.fasta` (multi-FASTA, unaligned) | `tool_outputs/mafft_aligned.fasta` | Aligned FASTA with `-` gaps | Yes. Used by alignment-dependent Stage 2 tools such as **varVAMP**, **Primer Prospector**, **DegePrime**, and potentially **PMPrimer** if aligned input is needed. |
| **Clustal Omega** | 1 | Working | `test5.fasta` (multi-FASTA, unaligned) | `tool_outputs/clustalo_aligned.fasta` | Aligned FASTA with `-` gaps | Would be interchangeable with MAFFT output for downstream alignment-based tools. |
| **Primer3 (primer3_core)** | 2a | Working | `tool_outputs/primer3_input.txt` (Boulder-IO text) | `tool_outputs/primer3_output.txt` (Boulder-IO text) | Key-value output such as `PRIMER_LEFT_0_SEQUENCE=TCGAACTGCACCTCATGGTC`, `PRIMER_RIGHT_0_TM=59.970`, `PRIMER_PAIR_0_PRODUCT_SIZE=198` | Yes. Stage 3 demo primers and Stage 4 scoring are derived from Primer3 output fields: `PRIMER_LEFT_i_SEQUENCE`, `PRIMER_RIGHT_i_SEQUENCE`, `PRIMER_LEFT_i_TM`, `PRIMER_RIGHT_i_TM`, `PRIMER_PAIR_i_PRODUCT_SIZE`. |
| **primer3-py** | 2b | Working, but demo only | Python dict inside `tool_outputs/primer3py_demo.py` | Printed to stdout only | Printed structured results: left/right primer sequences, Tm, product size | No. Not saved to file, so not consumed by later stages in your pipeline. |
| **EMBOSS eprimer3** | 2c | Runs, but no usable primer rows shown | `tool_outputs/single_seq.fasta` (single-sequence FASTA) | `tool_outputs/eprimer3_output.txt` | EMBOSS primer report. In your run only header lines appeared, e.g. `# EPRIMER3 RESULTS FOR MN908947.3` | No. Since it did not produce usable primer rows in the demo, it was not used downstream. |
| **PMPrimer** | 2d | Installed, but demo run failed / not usable yet | Intended input: multi-FASTA, preferably aligned FASTA for your case. You tried `test5.fasta` and `tool_outputs/mafft_aligned.fasta` | Expected saved result tables / evaluation outputs; actual run logs in `tool_outputs/pmprimer_run.log` / `tool_outputs/pmprimer_debug.log` | Expected: conserved-region summaries, candidate primer tables, evaluation summaries. Actual issues seen: “Sequences Not Align Yet”, then “Cannot Detect Enough Conserved Region”, and MUSCLE alignment exception. | No. No usable PMPrimer output file was produced for later stages. |
| **primerdiffer** | 2e | Installed, but not runnable with current demo inputs | Needs `target.fasta`, `nontarget.fasta`, plus a biologically meaningful `-pos` region; optional VCF | Expected discriminatory primer TSV/CSV | Expected fields: primer sequences, Tm, GC%, mismatch positions, specificity against non-target | No. Not run because your explorer demo does not provide the required two-genome setup plus valid coordinates. |
| **Primer Prospector** | 2f | Not installed | Expected input: aligned FASTA such as `tool_outputs/mafft_aligned.fasta` | Expected outputs: `primers.txt`, `primer_hits.txt` | Expected fields: primer sequence, number of hits, percent coverage, average mismatches |  |
| **PUPpy** | 2g | Not installed | Expected input: `ResultDB.tsv` + CDS directory | Expected TSV tables and plots | Expected fields: primer name, sequence, Tm, GC%, target gene; specificity/coverage plots |  |
| **DegePrime** | 2h | Not installed | Expected input: trimmed aligned FASTA, e.g. from MAFFT then trimming | Expected output: `degeprime_output.tsv` | Expected columns: `position`, `primer_seq`, `degeneracy`, `coverage`, `matching_seqs` |  |
| **HYDEN** | 2i | Not installed | Expected input: FASTA of sequences + primer constraints | Usually stdout or text output | Expected degenerate primer pairs with degeneracy and coverage values | |
| **PrimalScheme** | 2j | Not installed | Expected input: reference FASTA / viral genome FASTA | Expected output directory with BED/TSV/JSON files | Expected outputs: `scheme.primer.bed`, `scheme.primer.tsv`, `scheme.report.json`, intermediate work files | |
| **varVAMP** | 2k | Working | `tool_outputs/mafft_aligned.fasta` (MSA FASTA) | `tool_outputs/varvamp_output/` (output directory) | Actual run progressed through config check, preprocessing, consensus creation, primer finding, kmer digestion, filtering, overlap exclusion, and potential amplicon creation. Expected final outputs are primer/amplicon scheme files in output dir. | Not consumed by your current Stage 3/4 script. It is an alternative multi-stage design route, not part of the Primer3→BLAST/ipcress→greedy-ranker path. |
| **NGS-PrimerPlex** | 2l | Not installed | Expected input: `targets.bed` + reference genome FASTA | Expected multiplex design files / reports | Expected outputs: primer tables, multiplex compatibility reports, coverage/dimer analysis |  Not available via normal `pip` in your environment; would likely require GitHub/manual/Docker install. |
| **BLAST+ makeblastdb** | 3a | Working | `test5.fasta` (multi-FASTA) | `tool_outputs/blastdb/sars2.*` | BLAST nucleotide database files: `.ndb`, `.nhr`, `.nin`, `.nsq`, etc. | Yes. Supplies database for **blastn-short**. |
| **BLAST+ blastn-short** | 3b | Working | `tool_outputs/primers_query.fasta` + `tool_outputs/blastdb/sars2` | `tool_outputs/blastn_short_output.txt` | Tabular BLAST outfmt 6 lines such as `left_primer MN908947.3 100.000 20 ...` | Yes. Stage 4 scoring script counts hits per `qseqid` and converts them into `blast_off_target` penalties. |
| **MFEprimer** | 3c | Not installed | Expected input: primer FASTA + indexed database / genome FASTA | Expected QC report | Expected fields: Tm, GC%, hairpin ΔG, dimer ΔG, binding counts / specificity metrics | Could have contributed stronger QC features to Stage 4 if installed. |
| **UCSC isPcr** | 3d | Not installed | Expected input: genome `.2bit` + primer TSV | Expected amplicon output text/FASTA | Expected outputs: amplicon sequences with genomic coordinates |  |
| **Exonerate ipcress** | 3e | Working | `tool_outputs/ipcress_primers.txt` + `test5.fasta` | `tool_outputs/ipcress_output.txt` | Amplimer report plus machine-parseable lines like `ipcress: MN908947.3:filter(unmasked) pair1 198 A 492 0 B 670 0 forward` | Yes. Stage 4 scoring adapter parses `ipcress:` lines and counts amplimers per assay (`pair1`, `pair2`, etc.) into `amplimer_hits`. |
| **EMBOSS primersearch** | 3f | Working | `tool_outputs/primersearch_primers.txt` + `test5.fasta` | `tool_outputs/primersearch_output.txt` | Text report with blocks like `Primer name pair1`, `Amplimer 1`, sequence, strand hits, amplicon length | Yes. Stage 4 scoring adapter counts `Amplimer` blocks per primer pair and adds them into `amplimer_hits`. |
| **tntblast** | 3g | Not installed | Expected input: assay file + FASTA/DB | Expected tabular report | Expected fields: assay name, target ID, fwd/rev Tm, amplicon start/end/length, mismatches | = |
| **VirtualPCR** | 3h | Not installed | Expected input: config file + FASTA | Expected PCR prediction report | Expected fields: target ID, amplicon start/end, product size, primer binding positions, mismatch count |  |
| **Scoring adapter (`scoring_adapter.py`)** | 4a bridge | Working (custom script) | `tool_outputs/primer3_output.txt`, `tool_outputs/blastn_short_output.txt`, `tool_outputs/ipcress_output.txt`, `tool_outputs/primersearch_output.txt` | `tool_outputs/stage4_scored_pairs.json` | JSON array with fields like `pair_id`, `left_sequence`, `right_sequence`, `amplicon_size`, `left_tm`, `right_tm`, `tm_diff`, `blast_off_target`, `amplimer_hits`, penalties, `final_score` | Yes. Direct input to greedy ranker. This is the actual Stage 3→4 bridge in your pipeline. |
| **Greedy Ranker (`greedy_ranker.py`)** | 4a | Working (custom script, not third-party tool) | `tool_outputs/stage4_scored_pairs.json` | `tool_outputs/stage4_final_panel.json` | JSON array of selected non-conflicting pairs. Example: `{"pair_id":"P_002","left_sequence":"TGTCGTTGACAGGACACGAG",...,"final_score":99.86}` | Final output. No further tool consumes it in your current explorer script. |
| **Olivar** | 4b | Not installed | Expected input: reference FASTA or design DB | Expected output: BED/TSV/JSON/config files | Expected outputs: `primer.bed`, `primer.tsv`, `amplicon.bed`, `config.json` |  |
| **multiPrime** | 4c | Not installed | Expected input: config YAML + FASTA via Snakemake workflow | Expected minimal primer set files | Expected outputs: `minimal_primers.tsv`, `coverage_report.txt` |  |
| **PrimalScheme3** | 4d | Installed, but only help/CLI confirmed so far | Expected input: existing scheme BED + alignment FASTA | Expected outputs: interaction report / repaired scheme | Expected outputs: `interactions.tsv`, repaired BED, repair report JSON | It was detected successfully, but not yet run on real scheme files. |
| **openPrimeR** | 4e | Not installed | Expected input: templates FASTA + candidate primer sets (CSV/FASTA), run from R | Expected optimized primer CSV and plots | Expected fields: primer ID, sequence, Tm, GC%, coverage percent | |





Here's the clean markdown:

---

## Evidence and Notes

- **Primer3 output:** The run log shows Primer3's Boulder-IO output file with primers. Example log lines:

```
File: tool_outputs/primer3_output.txt
PRIMER_LEFT_0_SEQUENCE=TCGAACTGCACCTCATGGTC
PRIMER_RIGHT_0_TM=59.970
```

(Only the first pair was shown, but 5 pairs were returned.) These fields feed into the scoring script.

- **BLAST results:** `blastn-short` produced many hits. The table includes lines like:

```
left_primer MN908947.3 100.000 20 0 0 ...
right_primer MN908947.3 100.000 20 0 0 ...
```

indicating 100% matches of each primer to multiple SARS-CoV-2 sequences.

- **In-silico PCR:** The `ipcress` and `primersearch` outputs confirmed exact 20/20 matches (no mismatches) with expected products (198 bp) in the target genomes:
  - `ipcress` lines (abbreviated):
    ```
    ipcress: MN908947.3:filter(...) pair1 198 A 492 0 B 670 0 forward
    ```
  - `primersearch` output (abbreviated):
    ```
    Primer name pair1
    Amplimer 1 Sequence: MN908947.3
      TCGAACTGCACCTCATGGTC hits forward strand at 493 with 0 mismatches
      ...Amplimer length: 198 bp
    ```

- **Scoring and ranker:** The scoring adapter printed the ordered scores (only top 5 pairs):

```
P_002  score=99.86  amp=218bp  blast_off=0  amplimers=0
P_003  score=99.86  amp=214bp  blast_off=0  amplimers=0
...
P_001  score=25.86  amp=198bp  blast_off=8  amplimers=10
```

Greedy ranker then selected P_002 and P_003 (skipping others due to primer reuse):

```
SELECT P_002  score=99.86  amp=218bp
SELECT P_003  score=99.86  amp=214bp
```

- **Caveats:** Only the **top-scoring** Primer3 pairs were ultimately used in testing. `eprimer3` and some other tools were skipped or produced no usable output. `primer3-py`'s output was printed to console only and was not saved as a file, so it did not feed into the pipeline.

- **PMPrimer status:** PMPrimer is now confirmed to be **installed**, because its help command ran successfully. However, it did **not** produce usable design output in this dataset. When run on raw `test5.fasta`, it reported:

```
Sequences Not Align Yet
```

meaning it expects aligned input. When run on `tool_outputs/mafft_aligned.fasta`, it reported:

```
Shannon Terminate Or Continue Cannot Detect Enough Conserved Region
```

meaning PMPrimer could not find enough conserved regions under the current alignment/settings to continue primer design. When asked to perform its own MUSCLE alignment, it failed with:

```
MUSCLE 多序列比对异常
```

so PMPrimer should be classified as **installed but not successfully producing primers in this run**.

- **varVAMP status:** varVAMP is now confirmed to be **working** The successful run:

```
varvamp tiled tool_outputs/mafft_aligned.fasta tool_outputs/varvamp_output
```

progressed through preprocessing, consensus generation, primer filtering, amplicon finding, and scheme creation. This means varVAMP is a real working alternative Stage 2–4 workflow in the environment. Its outputs were not used by the custom Primer3 → Stage 3 → Stage 4 scoring pipeline, but the tool itself ran successfully.

- **PrimalScheme3 status:** PrimalScheme3 is now confirmed to be **installed**, because `primalscheme3 --help` worked and displayed its CLI structure. However, it was **not yet run on a real input scheme**, because it requires an existing primer BED file and usually an alignment or scheme file from a prior tiling workflow. So it is installed, but not demonstrated end-to-end in this explorer run.

- **`eprimer3` interpretation:** `eprimer3` did execute and write `tool_outputs/eprimer3_output.txt`, but the report only contained the header and no primer rows. Since `primer3_core` found valid primers on the same sequence, this suggests the problem is more likely **wrapper behavior, EMBOSS filtering rules, or report formatting**, rather than absence of possible primers in the template.

- **primerdiffer interpretation:** `primerdesign.py` is present, so primerdiffer is at least partially installed. But it was not run live because it needs:
  - a real `target.fasta`
  - a real `nontarget.fasta`
  - a biologically meaningful `-pos` region

  In earlier debugging, it also failed with:

  ```
  ModuleNotFoundError: No module named 'Bio.Blast.Applications'
  ```

  which suggests an environment compatibility issue with the installed Biopython version. So primerdiffer is best described as **detected, but not currently runnable without both proper demo inputs and dependency adjustment**.

- **Not-installed tools:** Several tools remained unavailable because the script could not find their executables or runnable modules in the environment. These include:
  - Primer Prospector
  - PUPpy
  - DegePrime
  - HYDEN
  - PrimalScheme
  - NGS-PrimerPlex
  - MFEprimer
  - isPcr / faToTwoBit
  - tntblast
  - VirtualPCR
  - Olivar
  - multiPrime
  - openPrimeR

  For these tools, the script could only document the **expected input/output**, not real produced files.

- **NGS-PrimerPlex note:** NGS-PrimerPlex was not installable through normal `pip install` in this environment. Earlier checks showed:

```
ERROR: No matching distribution found for NGS-PrimerPlex
```

so its practical installation path appears to be GitHub or Docker-based rather than a standard PyPI package install here.


- **Meaning of the final selected panel:** The final panel JSON:

```
tool_outputs/stage4_final_panel.json
```

is the output of the **custom Greedy Ranker script**, not an external software package. It simply chooses the highest-scoring primer pairs while preventing reuse of the same primer sequence across multiple selected pairs.

