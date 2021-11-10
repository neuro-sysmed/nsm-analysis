version 1.0


# Relative to wf file!

import "../tasks/Utils.wdl" as Utils
import "../tasks/Versions.wdl" as Versions

workflow Versions_test {

   input {
      String? image
      String? version_file
      String? bcftools_module
      String? bedtools_module
      String? gatk_module
      String? picard_module
      String? salmon_module
      String? samtools_module
      String? star_module
      String? bwa_module
   }

   
   call Versions.Versions as Versions {
      input:
         image = image,
         version_file = version_file,
         bcftools_module = bcftools_module,
         bedtools_module = bedtools_module,
         gatk_module = gatk_module,
         picard_module = picard_module,
         salmon_module = salmon_module,
         samtools_module = samtools_module,
         star_module = star_module,
         bwa_module = bwa_module
   }



   # call Utils.WriteStringsToFile as RunInfo {
   #    input:
   #       strings = ["workflow\tdna-pipeline",
   #                  "bwa\t"+Versions.bwa,
   #                  "picard\t"+Versions.picard,
   #                  "gatk\t"+Versions.gatk,
   #                  "samtools\t"+Versions.samtools,
   #                  "nsm-analysis\t"+Versions.package,
   #                  "image\t"+Versions.image,
   #                  "singularity\t"+Versions.singularity,
   #                  "bcftools\t"+Versions.bcftools,
   #                  "bedtools\t"+Versions.bedtools,
   #                  "star\t"+Versions.star,
   #                  "salmon\t"+Versions.salmon,
   #                ],
   #       outfile = "versions.runinfo"
   # }


  output {

#      File runinfo = RunInfo.outfile
   }




  meta {
    allowNestedInputs: true
  }

}

