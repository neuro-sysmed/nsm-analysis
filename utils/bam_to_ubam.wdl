version 1.0

import "../tasks/BamUtils.wdl" as BamUtils


workflow BamToUnalignedBam {

   input {
      Array[String] bams
      String unmapped_bam_suffix = ".ubam"
      String mapped_bam_suffix = ".bam"
      String outdir = "."
   }

   scatter (input_bam in bams) {

      String bam_basename = basename(input_bam, mapped_bam_suffix)

      call BamUtils.RevertSam as RevertSam {
         input:
            input_bam = input_bam,
            output_bam_filename = bam_basename + unmapped_bam_suffix,
            outdir = outdir
      }
   }

   output {
      Array[File] split_bams = RevertSam.output_bam
   }


   meta {
      allowNestedInputs: true
   }

}

