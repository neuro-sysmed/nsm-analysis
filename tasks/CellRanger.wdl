version 1.0

task Count {
  input {
      String id
      Array[File] fastqs
      String transcriptome
      String cellranger_cmd = "/usr/local/bin/cellranger"
  }

  command {
      ~{cellranger_cmd} count --id=~{id} \
                 --transcriptome=~{transcriptome} \
                 --fastqs= ~{sep=","  fastqs}

  }

  output {
    File outputdir = "out/"
  }
}




