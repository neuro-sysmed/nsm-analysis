version 1.0

task Count {
  input {
      String id
      Array[File] fastqs
      String transcriptome
      String cellranger_cmd = "cellranger"
      String? cellranger_module
  }

  command {
    if [[ ! -z "~{cellranger_module}" ]]; then
        module load ~{cellranger_module}
    fi

      ~{cellranger_cmd} count --id=~{id} \
                 --transcriptome=~{transcriptome} \
                 --fastqs= ~{sep=","  fastqs}

  }

  output {
    File outputdir = "out/"
  }
}




