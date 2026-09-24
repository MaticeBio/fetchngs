Fixtures for `../unpaired.nf.test`.

Each directory stands in for one `SRATOOLS_PREFETCH` output. The fake
`fasterq-dump` that `../unpaired.config` puts on PATH reads its `plan` and writes
one FASTQ per line — the line is the suffix appended to `--outfile`, and `-` means
the unsuffixed file `--split-3` writes its mate-less spots to.

  pe_with_orphans            _1, _2 and an orphan: the case the fork exists for.
  pe_with_orphans_technical  _1, _2, a technical _3 and an orphan
                             (`--include-technical`, which scrnaseq fetches need).
  pe_clean                   _1, _2 only: `--split-3` on a run with no orphans.
  only_unsuffixed            one unsuffixed file and nothing else — a single-end
                             run, and the run ENA labels PAIRED whose every spot
                             carries a single read.
