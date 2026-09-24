process SRATOOLS_FASTERQDUMP {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-5f89fe0cd045cb1d615630b9261a1d17943a9b6a:6a9ff0e76ec016c3d0d27e0c0d362339f2d787e6-0' :
        'quay.io/biocontainers/mulled-v2-5f89fe0cd045cb1d615630b9261a1d17943a9b6a:6a9ff0e76ec016c3d0d27e0c0d362339f2d787e6-0' }"

    input:
    tuple val(meta), path(sra)
    path ncbi_settings
    path certificate

    output:
    tuple val(meta), path('*.fastq.gz')          , emit: reads
    tuple val(meta), path('*_unpaired.fastq.gz') , optional: true, emit: unpaired
    path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def args2 = task.ext.args2 ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def outfile = meta.single_end ? "${prefix}.fastq" : prefix
    // `--split-3` writes spots whose mate did not survive the submitter's QC to an
    // UNSUFFIXED file alongside <prefix>_1/_2. It must not be left under that name:
    // workflows/sra assigns fastq_1/fastq_2 positionally from a SORTED glob, and '.'
    // (0x2E) sorts before '_' (0x5F), so an orphan left here would take reads[0] —
    // the samplesheet would pair it with _1 and silently DROP _2, i.e. succeed with
    // mispaired reads rather than fail.
    //
    // The fix is a RENAME, not a move into a subdirectory. Renaming keeps the orphan
    // in the task root, where the module's one `*.fastq.gz` publishDir rule already
    // covers it. The nested `unpaired/` this replaces needed a SECOND publishDir entry
    // whose pattern carried a directory, and that entry published nothing at all
    // against a `gs://` outdir under `scratch = true` + `stageOutMode = 'copy'`: the
    // orphans reached the work dir and were then destroyed with it on success.
    //
    // `_unpaired` is SORT-SAFE, which is the whole property being bought back here.
    // Nextflow sorts a glob output's files (TaskFileCollector.fetchResultFiles ->
    // `files.sort()`), Path's natural order is lexicographic, and all three names
    // share the prefix `<prefix>_`, so the deciding characters are '1' (0x31) < '2'
    // (0x32) < 'u' (0x75). reads[0] is _1 and reads[1] is _2 exactly as before, and
    // workflows/sra reads no further index. It sorts after a technical `_3` too
    // (0x33 < 0x75), so an `--include-technical` dump is unaffected.
    //
    // Guarded on `_1` ALSO existing, not on the orphan file alone: if fasterq-dump
    // wrote <prefix>.fastq and nothing else — a run ENA labels PAIRED whose every spot
    // carries one read — then that file is not an orphan, it is the library's only
    // reads, and renaming it would label the whole library `_unpaired`. (The
    // `unpaired/` move this replaces had the same case and ended worse: it emptied the
    // non-optional `*.fastq.gz` glob and failed the task with MissingFileException.)
    //
    // A no-op under `--split-files`, which writes no unsuffixed file, and for
    // single-end runs, whose only output IS <prefix>.fastq.gz.
    def segregate_unpaired = meta.single_end ? '' : """
    if [ -f "${prefix}.fastq.gz" ] && [ -f "${prefix}_1.fastq.gz" ]; then
        mv "${prefix}.fastq.gz" "${prefix}_unpaired.fastq.gz"
    fi
    """
    def key_file = ''
    if (certificate.toString().endsWith('.jwt')) {
        key_file += " --perm ${certificate}"
    } else if (certificate.toString().endsWith('.ngc')) {
        key_file += " --ngc ${certificate}"
    }
    """
    export NCBI_SETTINGS="\$PWD/${ncbi_settings}"

    fasterq-dump \\
        $args \\
        --threads $task.cpus \\
        --outfile $outfile \\
        ${key_file} \\
        ${sra}

    pigz \\
        $args2 \\
        --no-name \\
        --processes $task.cpus \\
        *.fastq
    ${segregate_unpaired}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sratools: \$(fasterq-dump --version 2>&1 | grep -Eo '[0-9.]+')
        pigz: \$( pigz --version 2>&1 | sed 's/pigz //g' )
    END_VERSIONS
    """
}
