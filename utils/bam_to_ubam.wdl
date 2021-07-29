version 1.0

import "../tasks/BamUtils.wdl" as BamUtils
import "../tasks/Utils.wdl" as Utils
import "../tasks/Versions.wdl" as Versions


workflow BamToUnalignedBam {

   input {
      File input_bam
      String unmapped_bam_suffix = ".ubam"
      String mapped_bam_suffix = ".bam"
      String outdir = "."
   }

   String bam_basename = basename(input_bam, mapped_bam_suffix)

   call Versions.Versions as Versions


   call BamUtils.RevertSam as RevertSam {
      input:
         input_bam = input_bam,
         output_bam_filename = bam_basename + unmapped_bam_suffix,
         outdir = outdir
   }


    call Utils.WriteStringsToFile as RunInfo {
        input:
            strings = ["workflow\tBamToUnalignedBam",
                       "picard\t"+Versions.picard,            
                       "nsm-analysis\t"+Versions.package,
                       "image\t"+Versions.image],
            outfile = "~{sample_name}.runinfo"
    }
      


   output {
      File ubam = RevertSam.output_bam
      File runinfo = RunInfo.outfile
   }


   meta {
      allowNestedInputs: true
   }

}

