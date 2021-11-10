version 1.0


# Relative to wf file!

import "../tasks/Utils.wdl" as Utils
import "../tasks/Versions.wdl" as Versions

workflow DNAProcessing {

   input {
      Boolean UseModules = false
   }

   
   call Versions.Versions as Versions


   call Utils.WriteStringsToFile as RunInfo {
      input:
         strings = ["workflow\tdna-pipeline",
                    "bwa\t"+Versions.bwa,
                    "picard\t"+Versions.picard,
                    "gatk\t"+Versions.gatk,
                    "samtools\t"+Versions.samtools,
                    "nsm-analysis\t"+Versions.package,
                    "image\t"+Versions.image,
                    "singularity\t"+Versions.singularity,
                    "bcftools\t"+Versions.bcftools,
                    "bedtools\t"+Versions.bedtools,
                    "star\t"+Versions.star,
                    "salmon\t"+Versions.salmon,
                  ],
         outfile = "versions.runinfo"
   }


  output {

      File runinfo = RunInfo.outfile
   }




  meta {
    allowNestedInputs: true
  }

}

