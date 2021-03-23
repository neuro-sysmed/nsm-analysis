version 1.0



task FqToBam {
  input {
    File fq_fwd
    File fq_rev
    String output_bam_filename
    String readgroup
    String sample_name 
    String? library_name = "NA"
    Int? compression_level = 2
    String? outdir = "."
  }

  command {

    if [  "~{outdir}" != "." ]; then
      mkdir "~{outdir}/"
    fi

    java -Dsamjdk.compression_level=~{compression_level} -Xms4000m -jar /home/brugger/projects/nsm/nsm-analysis/software/picard.jar \
      FastqToSam \
      -FASTQ ~{fq_fwd} \
      -FASTQ2 ~{fq_rev} \
      -OUTPUT ~{output_bam_filename} \
      -READ_GROUP_NAME ~{readgroup} \
      -SAMPLE_NAME ~{sample_name} \
      -LIBRARY_NAME ~{library_name} 

  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
#    disks: "local-disk " + disk_size + " HDD"
    cpu: "1"
    memory: "5000 MiB"
#    preemptible: preemptible_tries
  }
  output {
    File output_bam = "~{outdir}/~{output_bam_filename}"
  }
}



