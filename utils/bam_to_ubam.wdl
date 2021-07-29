version 1.0

import "../tasks/BamUtils.wdl" as BamUtils


workflow BamsToUnalignedBams {

   input {
      File input_bam
      String unmapped_bam_suffix = ".ubam"
      String mapped_bam_suffix = ".bam"
      String outdir = "."
   }

   String bam_basename = basename(input_bam, mapped_bam_suffix)

   call BamUtils.RevertSam as RevertSam {
      input:
         input_bam = input_bam,
         output_bam_filename = bam_basename + unmapped_bam_suffix,
         outdir = outdir
   }

   output {
      File ubam = RevertSam.output_bam
   }


   meta {
      allowNestedInputs: true
   }

}

