version 1.0

import "../tasks/BamUtils.wdl" as BamUtils
import "../tasks/FqUtils.wdl" as FqUtils
import "../structs/DNASeqStructs.wdl"


workflow MakeUnalignedBam {

   input {
      Array[File] bams = []
      Array[SampleFQ] sample_fqs
      String output_bam_filename
   }


    scatter (sample_fq in sample_fqs) {

        call FqUtils.FqToBam as FqToBam {
            input:
                fq_fwd = sample_fq.fwd,
                fq_rev =  sample_fq.rev,
                output_bam_filename = "~{sample_fq.readgroup}.ubam",
                readgroup = "~{sample_fq.readgroup}",
                sample_name = sample_fq.sample_name,
                outdir = "."
        }


    }

    Array[String] bamfiles = flatten([bams, FqToBam.output_bam])

    call BamUtils.MergeUnalignedBams as MergeUnalignedBams {
        input:
            bams = bamfiles,
            output_bam_basename = output_bam_filename
    }




   output {
      File bam_file = MergeUnalignedBams.output_bam
   }


   meta {
      allowNestedInputs: true
   }

}

