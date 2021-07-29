version 1.0



task FqToBam {
  input {
    File fq_fwd
    File? fq_rev
    String output_bam_filename
    String readgroup
    String sample_name 
    String library_name = "NA"
    Int compression_level = 2
    String outdir = "."
    String picard_jar = "/usr/local/jars/picard.jar"

  }

  command {

    if [  "~{outdir}" != "." ]; then
      mkdir "~{outdir}/"
    fi


    if [[-z fq_rev]]; then
      java -Dsamjdk.compression_level=~{compression_level} -Xms4000m -jar ~{picard_jar} \
        FastqToSam \
        -FASTQ ~{fq_fwd} \
        -OUTPUT ~{output_bam_filename} \
        -READ_GROUP_NAME ~{readgroup} \
        -SAMPLE_NAME ~{sample_name} \
        -LIBRARY_NAME ~{library_name} 
    else
      java -Dsamjdk.compression_level=~{compression_level} -Xms4000m -jar ~{picard_jar} \
        FastqToSam \
        -FASTQ ~{fq_fwd} \
        -FASTQ2 ~{fq_rev} \
        -OUTPUT ~{output_bam_filename} \
        -READ_GROUP_NAME ~{readgroup} \
        -SAMPLE_NAME ~{sample_name} \
        -LIBRARY_NAME ~{library_name} 
    fi
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
#    disks: "local-disk " + disk_size + " HDD"
    cpus: 1
    memory: 5000
  }
  output {
    File output_bam = "~{outdir}/~{output_bam_filename}"
  }
}



