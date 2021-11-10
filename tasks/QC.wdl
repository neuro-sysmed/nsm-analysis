version 1.0


# Collect sequencing yield quality metrics
task CollectQualityYieldMetrics {
  input {
    File input_bam
    String metrics_filename
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }


  command {
    mkdir qc
    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi
    
    java -Xms2000m -jar $PICARD_JAR \
      CollectQualityYieldMetrics \
      INPUT=~{input_bam} \
      OQ=true \
      OUTPUT=qc/~{metrics_filename}
  }

  runtime {
   # docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
#    disks: "local-disk " + disk_size + " HDD"
    memory: 3000
  }

  output {
    File quality_yield_metrics = "qc/~{metrics_filename}"
  }
}

# Collect base quality and insert size metrics
task CollectUnsortedReadgroupBamQualityMetrics {
  input {
    File input_bam
    String output_bam_prefix
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }


  command {
    mkdir qc
    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms5000m -jar $PICARD_JAR \
      CollectMultipleMetrics \
      INPUT=~{input_bam} \
      OUTPUT=qc/~{output_bam_prefix} \
      ASSUME_SORTED=true \
      PROGRAM=null \
      PROGRAM=CollectBaseDistributionByCycle \
      PROGRAM=CollectInsertSizeMetrics \
      PROGRAM=MeanQualityByCycle \
      PROGRAM=QualityScoreDistribution \
      METRIC_ACCUMULATION_LEVEL=null \
      METRIC_ACCUMULATION_LEVEL=ALL_READS

    touch ~{output_bam_prefix}.insert_size_metrics
    touch ~{output_bam_prefix}.insert_size_histogram.pdf
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 6000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File base_distribution_by_cycle_pdf = "qc/~{output_bam_prefix}.base_distribution_by_cycle.pdf"
    File base_distribution_by_cycle_metrics = "qc/~{output_bam_prefix}.base_distribution_by_cycle_metrics"
    File insert_size_histogram_pdf = "qc/~{output_bam_prefix}.insert_size_histogram.pdf"
    File insert_size_metrics = "qc/~{output_bam_prefix}.insert_size_metrics"
    File quality_by_cycle_pdf = "qc/~{output_bam_prefix}.quality_by_cycle.pdf"
    File quality_by_cycle_metrics = "qc/~{output_bam_prefix}.quality_by_cycle_metrics"
    File quality_distribution_pdf = "qc/~{output_bam_prefix}.quality_distribution.pdf"
    File quality_distribution_metrics = "qc/~{output_bam_prefix}.quality_distribution_metrics"
  }
}

# Collect alignment summary and GC bias quality metrics
task CollectReadgroupBamQualityMetrics {
  input {
    File input_bam
    File input_bam_index
    String output_bam_prefix
    File ref_dict
    File ref_fasta
    File ref_fasta_index
    Boolean collect_gc_bias_metrics = true
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }

  Float ref_size = size(ref_fasta, "GiB") + size(ref_fasta_index, "GiB") + size(ref_dict, "GiB")
  Int disk_size = ceil(size(input_bam, "GiB") + ref_size) + 20

  command {
    mkdir qc
    # These are optionally generated, but need to exist for Cromwell's sake
    touch qc/~{output_bam_prefix}.gc_bias.detail_metrics \
      qc/~{output_bam_prefix}.gc_bias.pdf \
      qc/~{output_bam_prefix}.gc_bias.summary_metrics

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms5000m -jar $PICARD_JAR \
      CollectMultipleMetrics \
      INPUT=~{input_bam} \
      REFERENCE_SEQUENCE=~{ref_fasta} \
      OUTPUT=qc/~{output_bam_prefix} \
      ASSUME_SORTED=true \
      PROGRAM=null \
      PROGRAM=CollectAlignmentSummaryMetrics \
      ~{true='PROGRAM="CollectGcBiasMetrics"' false="" collect_gc_bias_metrics} \
      METRIC_ACCUMULATION_LEVEL=null \
      METRIC_ACCUMULATION_LEVEL=READ_GROUP
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 6000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File alignment_summary_metrics = "qc/~{output_bam_prefix}.alignment_summary_metrics"
    File gc_bias_detail_metrics = "qc/~{output_bam_prefix}.gc_bias.detail_metrics"
    File gc_bias_pdf = "qc/~{output_bam_prefix}.gc_bias.pdf"
    File gc_bias_summary_metrics = "qc/~{output_bam_prefix}.gc_bias.summary_metrics"
  }
}

# Collect quality metrics from the aggregated bam
task CollectAggregationMetrics {
  input {
    File input_bam
    File input_bam_index
    String output_bam_prefix
    File ref_dict
    File ref_fasta
    File ref_fasta_index
    Boolean collect_gc_bias_metrics = true
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
    Int memory = 5000
  }

  Float ref_size = size(ref_fasta, "GiB") + size(ref_fasta_index, "GiB") + size(ref_dict, "GiB")
  Int disk_size = ceil(size(input_bam, "GiB") + ref_size) + 20

  command {
    mkdir qc
    # These are optionally generated, but need to exist for Cromwell's sake
    touch qc/~{output_bam_prefix}.gc_bias.detail_metrics \
      qc/~{output_bam_prefix}.gc_bias.pdf \
      qc/~{output_bam_prefix}.gc_bias.summary_metrics \
      qc/~{output_bam_prefix}.insert_size_metrics \
      qc/~{output_bam_prefix}.insert_size_histogram.pdf

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms~{memory}m -jar $PICARD_JAR \
      CollectMultipleMetrics \
      INPUT=~{input_bam} \
      REFERENCE_SEQUENCE=~{ref_fasta} \
      OUTPUT=qc/~{output_bam_prefix} \
      ASSUME_SORTED=true \
      PROGRAM=null \
      PROGRAM=CollectAlignmentSummaryMetrics \
      PROGRAM=CollectInsertSizeMetrics \
      PROGRAM=CollectSequencingArtifactMetrics \
      PROGRAM=QualityScoreDistribution \
      ~{true='PROGRAM="CollectGcBiasMetrics"' false="" collect_gc_bias_metrics} \
      METRIC_ACCUMULATION_LEVEL=null \
      METRIC_ACCUMULATION_LEVEL=SAMPLE \
      METRIC_ACCUMULATION_LEVEL=LIBRARY
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: memory + 1000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File alignment_summary_metrics = "qc/~{output_bam_prefix}.alignment_summary_metrics"
    File bait_bias_detail_metrics = "qc/~{output_bam_prefix}.bait_bias_detail_metrics"
    File bait_bias_summary_metrics = "qc/~{output_bam_prefix}.bait_bias_summary_metrics"
    File gc_bias_detail_metrics = "qc/~{output_bam_prefix}.gc_bias.detail_metrics"
    File gc_bias_pdf = "qc/~{output_bam_prefix}.gc_bias.pdf"
    File gc_bias_summary_metrics = "qc/~{output_bam_prefix}.gc_bias.summary_metrics"
    File insert_size_histogram_pdf = "qc/~{output_bam_prefix}.insert_size_histogram.pdf"
    File insert_size_metrics = "qc/~{output_bam_prefix}.insert_size_metrics"
    File pre_adapter_detail_metrics = "qc/~{output_bam_prefix}.pre_adapter_detail_metrics"
    File pre_adapter_summary_metrics = "qc/~{output_bam_prefix}.pre_adapter_summary_metrics"
    File quality_distribution_pdf = "qc/~{output_bam_prefix}.quality_distribution.pdf"
    File quality_distribution_metrics = "qc/~{output_bam_prefix}.quality_distribution_metrics"
    File error_summary_metrics = "qc/~{output_bam_prefix}.error_summary_metrics"
  }
}

task ConvertSequencingArtifactToOxoG {
  input {
    File pre_adapter_detail_metrics
    File bait_bias_detail_metrics
    String base_name
    File ref_dict
    File ref_fasta
    File ref_fasta_index
    Int memory_multiplier = 1
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }

  Float ref_size = size(ref_fasta, "GiB") + size(ref_fasta_index, "GiB") + size(ref_dict, "GiB")
  Int disk_size = ceil(size(pre_adapter_detail_metrics, "GiB") + size(bait_bias_detail_metrics, "GiB") + ref_size) + 20

  Int memory_size = ceil(4 * memory_multiplier)
  Int java_memory_size = (memory_size - 1) * 1000

  command {
    input_base=$(dirname ~{pre_adapter_detail_metrics})/~{base_name}
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms~{java_memory_size}m -jar $PICARD_JAR \
      ConvertSequencingArtifactToOxoG \
      --INPUT_BASE $input_base \
      --OUTPUT_BASE qc/~{base_name} \
      --REFERENCE_SEQUENCE ~{ref_fasta}
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: java_memory_size + 1000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File oxog_metrics = "qc/~{base_name}.oxog_metrics"
  }
}

# Check that the fingerprints of separate readgroups all match
task CrossCheckFingerprints {
  input {
    Array[File] input_bams
    Array[File] input_bam_indexes
    File haplotype_database_file
    String metrics_filename
    Float total_input_size
    Float lod_threshold
    String cross_check_by
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }

  Int disk_size = ceil(total_input_size) + 20

  command <<<
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Dsamjdk.buffer_size=131072 \
      -XX:GCTimeLimit=50 -XX:GCHeapFreeLimit=10 -Xms3000m \
      -jar $PICARD_JAR \
      CrosscheckFingerprints \
      OUTPUT=qc/~{metrics_filename} \
      HAPLOTYPE_MAP=~{haplotype_database_file} \
      EXPECT_ALL_GROUPS_TO_MATCH=true \
      INPUT=~{sep=' INPUT=' input_bams} \
      LOD_THRESHOLD=~{lod_threshold} \
      CROSSCHECK_BY=~{cross_check_by}
  >>>
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 3500
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File cross_check_fingerprints_metrics = "qc/~{metrics_filename}"
  }
}

# Check that the fingerprint of the sample BAM matches the sample array
task CheckFingerprint {
  input {
    File input_bam
    File input_bam_index
    String output_basename
    File haplotype_database_file
    File? genotypes
    File? genotypes_index
    String sample
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }

  Int disk_size = ceil(size(input_bam, "GiB")) + 20
  # Picard has different behavior depending on whether or not the OUTPUT parameter ends with a '.', so we are explicitly
  #   passing in where we want the two metrics files to go to avoid any potential confusion.
  String summary_metrics_location = "qc/~{output_basename}.fingerprinting_summary_metrics"
  String detail_metrics_location = "qc/~{output_basename}.fingerprinting_detail_metrics"

  command <<<
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Dsamjdk.buffer_size=131072 \
      -XX:GCTimeLimit=50 -XX:GCHeapFreeLimit=10 -Xms3g  \
      -jar $PICARD_JAR \
      CheckFingerprint \
      INPUT=~{input_bam} \
      SUMMARY_OUTPUT=qc/~{summary_metrics_location} \
      DETAIL_OUTPUT=qc/~{detail_metrics_location} \
      GENOTYPES=~{genotypes} \
      HAPLOTYPE_MAP=~{haplotype_database_file} \
      SAMPLE_ALIAS="~{sample}" \
      IGNORE_READ_GROUPS=true

  >>>
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 3500
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File summary_metrics = summary_metrics_location
    File detail_metrics = detail_metrics_location
  }
}

task CheckPreValidation {
  input {
    File duplication_metrics
    File chimerism_metrics
    Float max_duplication_in_reasonable_sample
    Float max_chimerism_in_reasonable_sample
  }

  command <<<
    set -o pipefail
    set -e

    grep -A 1 PERCENT_DUPLICATION ~{duplication_metrics} > duplication.csv
    grep -A 3 PCT_CHIMERAS ~{chimerism_metrics} | grep -v OF_PAIR > chimerism.csv

    python <<CODE

    import csv
    with open('duplication.csv') as dupfile:
      reader = csv.DictReader(dupfile, delimiter='\t')
      for row in reader:
        with open("duplication_value.txt","w") as file:
          file.write(row['PERCENT_DUPLICATION'])
          file.close()

    with open('chimerism.csv') as chimfile:
      reader = csv.DictReader(chimfile, delimiter='\t')
      for row in reader:
        with open("chimerism_value.txt","w") as file:
          file.write(row['PCT_CHIMERAS'])
          file.close()

    CODE

  >>>
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.7-1603303710"
#    docker: "us.gcr.io/broad-gotc-prod/python:2.7"
    memory: 2000
  }
  output {
    Float duplication_rate = read_float("duplication_value.txt")
    Float chimerism_rate = read_float("chimerism_value.txt")
    Boolean is_outlier_data = duplication_rate > max_duplication_in_reasonable_sample || chimerism_rate > max_chimerism_in_reasonable_sample
  }
}

task ValidateSamFile {
  input {
    File input_bam
    File? input_bam_index
    String report_filename
    File ref_dict
    File ref_fasta
    File ref_fasta_index
    Int? max_output
    Array[String]? ignore
    Boolean? is_outlier_data
    Int memory_multiplier = 1
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }

  Int memory_size = ceil(7 * memory_multiplier)
  Int java_memory_size = (memory_size - 1) * 1000

  command {
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms~{java_memory_size}m -jar $PICARD_JAR \
      ValidateSamFile \
      INPUT=~{input_bam} \
      OUTPUT=qc/~{report_filename} \
      REFERENCE_SEQUENCE=~{ref_fasta} \
      ~{"MAX_OUTPUT=" + max_output} \
      IGNORE=~{default="null" sep=" IGNORE=" ignore} \
      MODE=VERBOSE \
      ~{default='SKIP_MATE_VALIDATION=false' true='SKIP_MATE_VALIDATION=true' false='SKIP_MATE_VALIDATION=false' is_outlier_data} \
      IS_BISULFITE_SEQUENCED=false
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: java_memory_size+1000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File report = "qc/~{report_filename}"
  }
}

# Note these tasks will break if the read lengths in the bam are greater than 250.
task CollectWgsMetrics {
  input {
    File input_bam
    File input_bam_index
    String metrics_filename
    File wgs_coverage_interval_list
    File ref_fasta
    File ref_fasta_index
    Int read_length
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }

  command {
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms2000m -jar $PICARD_JAR \
      CollectWgsMetrics \
      INPUT=~{input_bam} \
      VALIDATION_STRINGENCY=SILENT \
      REFERENCE_SEQUENCE=~{ref_fasta} \
      INCLUDE_BQ_HISTOGRAM=true \
      INTERVALS=~{wgs_coverage_interval_list} \
      OUTPUT=qc/~{metrics_filename} \
      USE_FAST_ALGORITHM=true \
      READ_LENGTH=~{read_length}
  }
  runtime {
    #docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 3000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File metrics = "qc/~{metrics_filename}"
  }
}

# Collect raw WGS metrics (commonly used QC thresholds)
task CollectRawWgsMetrics {
  input {
    File input_bam
    File input_bam_index
    String metrics_filename
    File wgs_coverage_interval_list
    File ref_fasta
    File ref_fasta_index
    Int read_length
    Int memory_multiplier = 1
    Int additional_disk = 20
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }

  Float ref_size = size(ref_fasta, "GiB") + size(ref_fasta_index, "GiB")
  Int disk_size = ceil(size(input_bam, "GiB") + ref_size) + additional_disk

  Int memory_size = ceil((if (disk_size < 110) then 5 else 7) * memory_multiplier)
  String java_memory_size = (memory_size - 1) * 1000

  command {
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms~{java_memory_size}m -jar $PICARD_JAR \
      CollectRawWgsMetrics \
      INPUT=~{input_bam} \
      VALIDATION_STRINGENCY=SILENT \
      REFERENCE_SEQUENCE=~{ref_fasta} \
      INCLUDE_BQ_HISTOGRAM=true \
      INTERVALS=~{wgs_coverage_interval_list} \
      OUTPUT=qc/~{metrics_filename} \
      USE_FAST_ALGORITHM=true \
      READ_LENGTH=~{read_length}
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: java_memory_size+1000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File metrics = "qc/~{metrics_filename}"
  }
}

# Note these tasks will break if the read lengths in the bam are greater than 250.
task CollectRnaSeqMetrics {
  input {
    File input_bam
    File input_bam_index
    String metrics_filename
    File wgs_coverage_interval_list
    File ref_fasta
    File ref_fasta_index
    Int read_length
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }


  command {
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms2000m -jar $PICARD_JAR \
      CollectRnaSeqMetrics \
      INPUT=~{input_bam} \
      VALIDATION_STRINGENCY=SILENT \
      REFERENCE_SEQUENCE=~{ref_fasta} \
      INCLUDE_BQ_HISTOGRAM=true \
      INTERVALS=~{wgs_coverage_interval_list} \
      OUTPUT=qc/~{metrics_filename} \
      USE_FAST_ALGORITHM=true \
      READ_LENGTH=~{read_length}
  }
  runtime {
    #docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 3000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File metrics = "qc/~{metrics_filename}"
  }
}



task CollectHsMetrics {
  input {
    File input_bam
    File input_bam_index
    File ref_fasta
    File ref_fasta_index
    String metrics_filename
    File target_interval_list
    File bait_interval_list
    Int memory_multiplier = 1
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }

  # Try to fit the input bam into memory, within reason.
  Int rounded_bam_size = ceil(size(input_bam, "GiB") + 0.5)
  Int rounded_memory_size = ceil((if (rounded_bam_size > 10) then 10 else rounded_bam_size) * memory_multiplier)
  Int memory_size = if rounded_memory_size < 7 then 7 else rounded_memory_size
  Int java_memory_size = (memory_size - 1) * 1000

  # There are probably more metrics we want to generate with this tool
  command {
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms~{java_memory_size}m -jar $PICARD_JAR \
      CollectHsMetrics \
      INPUT=~{input_bam} \
      REFERENCE_SEQUENCE=~{ref_fasta} \
      VALIDATION_STRINGENCY=SILENT \
      TARGET_INTERVALS=~{target_interval_list} \
      BAIT_INTERVALS=~{bait_interval_list} \
      METRIC_ACCUMULATION_LEVEL=null \
      METRIC_ACCUMULATION_LEVEL=SAMPLE \
      METRIC_ACCUMULATION_LEVEL=LIBRARY \
      OUTPUT=qc/~{metrics_filename}
  }

  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: java_memory_size+1000
#    disks: "local-disk " + disk_size + " HDD"
  }

  output {
    File metrics = "qc/~{metrics_filename}"
  }
}

# Generate a checksum per readgroup
task CalculateReadGroupChecksum {
  input {
    File input_bam
    File input_bam_index
    String read_group_md5_filename
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }


  command {
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms1000m -jar $PICARD_JAR \
      CalculateReadGroupChecksum \
      INPUT=~{input_bam} \
      OUTPUT=qc/~{read_group_md5_filename}
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 1500
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File md5_file = "qc/~{read_group_md5_filename}"
  }
}

# Validate a (g)VCF with -gvcf specific validation
task ValidateVCF {
  input {
    File input_vcf
    File input_vcf_index
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File dbsnp_vcf
    File dbsnp_vcf_index
    File calling_interval_list
    Boolean is_gvcf = true
    String gatk_cmd = "/usr/local/bin/gatk"
  }


  command {
    ~{gatk_cmd} --java-options -Xms6000m \
      ValidateVariants \
      -V ~{input_vcf} \
      -R ~{ref_fasta} \
      -L ~{calling_interval_list} \
      ~{true="-gvcf" false="" is_gvcf} \
      --validation-type-to-exclude ALLELES \
      --dbsnp ~{dbsnp_vcf}
  }
  runtime {
    memory: 7000
  }
}

# Collect variant calling metrics from GVCF output
task CollectVariantCallingMetrics {
  input {
    File input_vcf
    File input_vcf_index
    String metrics_basename
    File dbsnp_vcf
    File dbsnp_vcf_index
    File ref_dict
    File evaluation_interval_list
    Boolean is_gvcf = true
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }


  command {
    mkdir qc

    PICARD_JAR=~{picard_jar}

    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms2000m -jar $PICARD_JAR \
      CollectVariantCallingMetrics \
      INPUT=~{input_vcf} \
      OUTPUT=qc/~{metrics_basename} \
      DBSNP=~{dbsnp_vcf} \
      SEQUENCE_DICTIONARY=~{ref_dict} \
      TARGET_INTERVALS=~{evaluation_interval_list} \
      ~{true="GVCF_INPUT=true" false="" is_gvcf}
  }
  runtime {
    memory: 3000
  }
  output {
    File summary_metrics = "qc/~{metrics_basename}.variant_calling_summary_metrics"
    File detail_metrics = "qc/~{metrics_basename}.variant_calling_detail_metrics"
  }
}

task FastQC {
  input {
    File infile
  }

  command {
    fastqc ~{infile}

  }

}
