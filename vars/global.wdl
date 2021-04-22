version 1.0

workflow global {
  output {
    String version = "v1.0.0"
    String reference  = "/home/brugger/projects/nsm/hg38_22"
    String reference_fasta  = "~{reference}/Homo_sapiens_assembly38_22.fasta"
    String bwa_cmd    = "/usr/local/bin/bwa"
    String picard_jar = "/usr/local/jars/picard.jar"
    String gatk_jar   = "/home/brugger/projects/nsm/nsm-analysis/software/gatk-package-4.2.0.0-local.jar"
    String samtools_cmd = "/home/brugger/bin/samtools"
  }
}

