version 1.0

import "../tasks/BamUtils.wdl" as BamUtils
import "../tasks/FqUtils.wdl" as FqUtils
import "../structs/DNASeqStructs.wdl"
import "../tasks/Utils.wdl" as Utils
import "../tasks/Versions.wdl" as Versions


workflow FqToUnalignedBam {

   input {
      File fq_fwd
      File? fq_rev
      String out_name
      String? readgroup
   }

   String final_readgroup = if defined(readgroup) then readgroup else out_name

   call Versions.Versions as Versions

   call FqUtils.FqToBam as FqToBam {
      input:
         fq_fwd = fq_fwd,
         fq_rev =  fq_rev,
         output_bam_filename = "~{out_name}.ubam",
         readgroup = "~{final_readgroup}",
         sample_name = sample_name,
         outdir = "."
   }

    call Utils.WriteStringsToFile as RunInfo {
        input:
            strings = ["workflow\tFqToUnalignedBam",
                       "picard\t"+Versions.picard,            
                       "nsm-analysis\t"+Versions.package,
                       "image\t"+Versions.image],
            outfile = "~{out_name}.runinfo"
    }


   output {
      File ubam = FqToBam.output_bam
      File runinfo = RunInfo.outfile
   }


   meta {
      allowNestedInputs: true
   }

}

