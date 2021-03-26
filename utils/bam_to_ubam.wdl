version 1.0

import "../tasks/BamUtils.wdl" as BamUtils


workflow BamToUnalignedBam {

   input {
      Array[String] bams
#      String? input_dir 
      String unmapped_bam_suffix
      String mapped_bam_suffix
   }

#   if (defined(input_dir)) {
#      Array[String] bams = glob("~{input_dir}/*.{mapped_bam_suffix}")
#   }


   scatter (input_bam in bams) {

      String bam_basename = basename(input_bam, mapped_bam_suffix)

      call BamUtils.RevertSam as RevertSam {
         input:
            input_bam = input_bam,
            output_bam_filename = bam_basename + unmapped_bam_suffix,
            outdir = "ubams"
      }
   }

   output {
      Array[File] split_bams = RevertSam.output_bam
   }


   meta {
      allowNestedInputs: true
   }

}

