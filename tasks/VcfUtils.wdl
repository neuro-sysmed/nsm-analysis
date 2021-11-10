version 1.0

import "../structs/DNASeqStructs.wdl"


# Combine multiple VCFs or GVCFs from scattered HaplotypeCaller runs
task MergeVCFs {
  input {
    Array[File] input_vcfs
    Array[File] input_vcfs_indexes
    String output_vcf_name
    String picard_jar = "/usr/local/jars/picard.jar"
    String? picard_module
  }


  # Using MergeVcfs instead of GatherVcfs so we can create indices
  # See https://github.com/broadinstitute/picard/issues/789 for relevant GatherVcfs ticket
  command {
    mkdir gvcfs

    PICARD_JAR=~{picard_jar}
    if [[ ! -z "~{picard_module}" ]]; then
        module load ~{picard_module}
    fi

    java -Xms2000m -jar $PICARD_JAR \
      MergeVcfs \
      -INPUT ~{sep=' -INPUT ' input_vcfs} \
      -OUTPUT gvcfs/~{output_vcf_name}
  }
  runtime {
    memory: 3000
  }
  output {
    File output_vcf = "gvcfs/~{output_vcf_name}"
    File output_vcf_index = "gvcfs/~{output_vcf_name}.tbi"
  }
}

task HardFilterVcf {
  input {
    File input_vcf
    File input_vcf_index
    String vcf_basename
    File interval_list
    String gatk_cmd = "gatk"
    String? gatk_module
  }

  Int disk_size = ceil(2 * size(input_vcf, "GiB")) + 20
  String output_vcf_name = vcf_basename + ".filtered.vcf.gz"

  command {
    if [[ ! -z "~{gatk_module}" ]]; then
        module load ~{gatk_module}
    fi

     ~{gatk_cmd} --java-options "-Xms3000m" \
      VariantFiltration \
      -V ~{input_vcf} \
      -L ~{interval_list} \
      --filter-expression "QD < 2.0 || FS > 30.0 || SOR > 3.0 || MQ < 40.0 || MQRankSum < -3.0 || ReadPosRankSum < -3.0" \
      --filter-name "HardFiltered" \
      -O ~{output_vcf_name}
  }
  output {
    File output_vcf = "~{output_vcf_name}"
    File output_vcf_index = "~{output_vcf_name}.tbi"
  }
  runtime {
#    docker: gatk_docker
    memory: 3000
  }
}

task CNNScoreVariants {
  input {
    File? bamout
    File? bamout_index
    File input_vcf
    File input_vcf_index
    String vcf_basename
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    String gatk_cmd = "gatk"
    String? gatk_module
  }

  String base_vcf = basename(input_vcf)
  Boolean is_compressed = basename(base_vcf, "gz") != base_vcf
  String vcf_suffix = if is_compressed then ".vcf.gz" else ".vcf"
  String vcf_index_suffix = if is_compressed then ".tbi" else ".idx"
  String output_vcf = base_vcf + ".scored" + vcf_suffix
  String output_vcf_index = output_vcf + vcf_index_suffix

  String bamout_param = if defined(bamout) then "-I ~{bamout}" else ""
  String tensor_type = if defined(bamout) then "read-tensor" else "reference"

  command {
    if [[ ! -z "~{gatk_module}" ]]; then
        module load ~{gatk_module}
    fi

    ~{gatk_cmd} --java-options -Xmx10g CNNScoreVariants \
       -V ~{input_vcf} \
       -R ~{ref_fasta} \
       -O ~{output_vcf} \
       ~{bamout_param} \
       -tensor-type ~{tensor_type}
  }

  output {
    File scored_vcf = "~{output_vcf}"
    File scored_vcf_index = "~{output_vcf_index}"
  }

  runtime {
#    docker: gatk_docker
    memory: 15000
    cpus: 2
  }
}

task FilterVariantTranches {

  input {
    File input_vcf
    File input_vcf_index
    String vcf_basename
    Array[String] snp_tranches
    Array[String] indel_tranches
    File hapmap_resource_vcf
    File hapmap_resource_vcf_index
    File omni_resource_vcf
    File omni_resource_vcf_index
    File one_thousand_genomes_resource_vcf
    File one_thousand_genomes_resource_vcf_index
    File dbsnp_resource_vcf
    File dbsnp_resource_vcf_index
    String info_key
    String gatk_cmd = "gatk"
    String? gatk_module

  }


  command {
    if [[ ! -z "~{gatk_module}" ]]; then
        module load ~{gatk_module}
    fi

    ~{gatk_cmd} --java-options -Xmx6g FilterVariantTranches \
      -V ~{input_vcf} \
      -O ~{vcf_basename}.filtered.vcf.gz \
      ~{sep=" " prefix("--snp-tranche ", snp_tranches)} \
      ~{sep=" " prefix("--indel-tranche ", indel_tranches)} \
      --resource ~{hapmap_resource_vcf} \
      --resource ~{omni_resource_vcf} \
      --resource ~{one_thousand_genomes_resource_vcf} \
      --resource ~{dbsnp_resource_vcf} \
      --info-key ~{info_key} \
      --create-output-variant-index true
  }

  output {
    File filtered_vcf = "~{vcf_basename}.filtered.vcf.gz"
    File filtered_vcf_index = "~{vcf_basename}.filtered.vcf.gz.tbi"
  }

  runtime {
    memory: 7000
    cpus: 2
  }
}

# Combine multiple VCFs or GVCFs from scattered HaplotypeCaller runs
task GenotypeGVCF {
  input {
    File input_gvcf
    File input_gvcf_index
    String output_vcf_name
    File reference_fasta
    File reference_fasta_index
    File reference_dict
    String gatk_cmd = "gatk"
    String gatk_module
  }


  # Using MergeVcfs instead of GatherVcfs so we can create indices
  # See https://github.com/broadinstitute/picard/issues/789 for relevant GatherVcfs ticket
  command {
    mkdir vcfs

    if [[ ! -z "~{gatk_module}" ]]; then
        module load ~{gatk_module}
    fi

    ~{gatk_cmd} GenotypeGVCFs \
      -R ~{reference_fasta} \
      -V ~{input_gvcf} \
      -O vcfs/~{output_vcf_name} \
      -G StandardAnnotation -G AS_StandardAnnotation 
  }

  runtime {
    memory: 3000
  }

  output {
    File output_vcf = "vcfs/~{output_vcf_name}"
    File output_vcf_index = "vcfs/~{output_vcf_name}.tbi"
  }
}
