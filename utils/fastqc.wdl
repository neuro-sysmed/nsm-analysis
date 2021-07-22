version 1.0

import "../tasks/QC.wdl" as QC


workflow FastQC {

    input {
      Array[File] infiles
    }

    scatter (filename in infiles) {

        call QC.FastQC as FQC {
            input:
                infile = filename
        }
    }

    output {
        Array[File] fastqc_outfiles = FQC.outfile

