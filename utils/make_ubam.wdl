version 1.0

import "../../../tasks/BamUtils.wdl" as BamUtils
import "../../../tasks/FqUtils.wdl" as FqUtils


workflow MergeFqBam {

   input {
      Array[File] bams = []
#      String? input_dir 
      Array[Map[String,String]] fqs
      String output_bam_filename
   }

#   if (defined(input_dir)) {
#      Array[String] bams = glob("~{input_dir}/*.{mapped_bam_suffix}")
#   }


    scatter (fq_set in fqs) {

        call FqUtils.FqToBam as FqToBam {
            input:
                fq_fwd = fq_set.fwd,
                fq_rev =  fq_set.rev,
                output_bam_filename = "~{fq_set.readgroup}.ubam",
                readgroup = "~{fq_set.readgroup}",
                sample_name = fq_set.sample_name,
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

