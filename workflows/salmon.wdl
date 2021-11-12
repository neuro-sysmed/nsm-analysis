version 1.0

import "../tasks/Versions.wdl" as Versions
import "../tasks/Alignment.wdl" as Alignment
import "../tasks/Utils.wdl" as Utils

workflow Salmon {

    input {
      String sample_name
      File fwd_reads
      File? rev_reads
      String reference_dir
      Int threads = 6
    }

    call Versions.Versions as Versions

    call Alignment.Salmon as Sal {
        input:
            sample_name = sample_name,
            fwd_reads = fwd_reads,
            rev_reads = rev_reads,
            reference_dir = reference_dir,
            threads = threads
   }

    call Utils.WriteStringsToFile as RunInfo {
        input:
            strings = ["workflow\tSalmon",
                       "salmon\t"+Versions.salmon,
                       "nsm-analysis\t"+Versions.package,
            outfile = "~{sample_name}.runinfo"
    }
      


   output {
    File flenDist = Sal.flenDist
    File quant = Sal.quant
    File cmdInfo = Sal.cmdInfo
    File libFormatCounts = Sal.libFormatCounts
    File log = Sal.log
    File ambigInfo = Sal.ambigInfo
    File fld = Sal.fld
    File obsBias = Sal.obsBias
    File expBias = Sal.expBias
    File obsBias3p = Sal.obsBias3p
    File metaInfo = Sal.metaInfo
    File runinfo = RunInfo.outfile
   }


   meta {
      allowNestedInputs: true
   }

}

