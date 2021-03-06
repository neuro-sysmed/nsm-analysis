version 1.0

## Copyright Broad Institute, 2018
##
## This WDL defines tasks used for BAM file processing of human whole-genome or exome sequencing data.
##
## Runtime parameters are often optimized for Broad's Google Cloud Platform implementation.
## For program versions, see docker containers.
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3) (see LICENSE in
## https://github.com/broadinstitute/wdl). Note however that the programs it calls may
## be subject to different licenses. Users are responsible for checking that they are
## authorized to run all programs before running this script. Please see the docker
## page at https://hub.docker.com/r/broadinstitute/genomes-in-the-cloud/ for detailed
## licensing information pertaining to the included programs.

# Sort BAM file by coordinate order
task SortSam {
  input {
    File input_bam
    String output_bam_basename
    Int compression_level
    String? picard_jar = "/usr/local/jars/picard.jar"

  }
  # SortSam spills to disk a lot more because we are only store 300000 records in RAM now because its faster for our data so it needs
  # more disk space.  Also it spills to disk in an uncompressed format so we need to account for that with a larger multiplier
  Float sort_sam_disk_multiplier = 3.25
  Int disk_size = ceil(sort_sam_disk_multiplier * size(input_bam, "GiB")) + 20

  command {
    mkdir bams
    java -Dsamjdk.compression_level=~{compression_level} -Xms4000m -jar ~{picard_jar} \
      SortSam \
      INPUT=~{input_bam} \
      OUTPUT=bams/~{output_bam_basename}.bam \
      SORT_ORDER="coordinate" \
      CREATE_INDEX=true \
      CREATE_MD5_FILE=true \
      MAX_RECORDS_IN_RAM=300000

  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
#    disks: "local-disk " + disk_size + " HDD"
    cpus: 1
    memory: 5000
  }
  output {
    File output_bam = "bams/~{output_bam_basename}.bam"
    File output_bam_index = "bams/~{output_bam_basename}.bai"
    File output_bam_md5 = "bams/~{output_bam_basename}.bam.md5"
  }
}

# Sort BAM file by coordinate order
task Index {
  input {
    File basename
    Int compression_level =5
    String? picard_jar = "/usr/local/jars/picard.jar"
  }

  command {
    java -Dsamjdk.compression_level=~{compression_level} -Xms4000m -jar ~{picard_jar} \
      BuildBamIndex \
      --INPUT "~{basename}.bam" \
      --CREATE_MD5_FILE true 

  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
#    disks: "local-disk " + disk_size + " HDD"
    cpus: 1
    memory: 5000
  }
  output {
    File output_bam_index = "~{basename}.bai"
    File output_bam_md5 = "~{basename}.bam.md5"
  }
}


task RevertSam {
  input {
    File input_bam
    String output_bam_filename
    Int compression_level = 2
    String picard_jar = "/usr/local/jars/picard.jar"
    String outdir = "."
  }

  command {

    if [  "~{outdir}" != "." ]; then
      mkdir "~{outdir}/"
    fi

    java -Dsamjdk.compression_level=~{compression_level} -Xms4000m -jar ~{picard_jar} \
     RevertSam \
     -I ~{input_bam} \
     -O ~{outdir}/~{output_bam_filename} \
     -SANITIZE true \
     -ATTRIBUTE_TO_CLEAR XT \
     -ATTRIBUTE_TO_CLEAR XN \
     -ATTRIBUTE_TO_CLEAR AS \
     -ATTRIBUTE_TO_CLEAR OC \
     -ATTRIBUTE_TO_CLEAR OP \
     -ATTRIBUTE_TO_CLEAR OA \
     -ATTRIBUTE_TO_CLEAR CO \
     -SORT_ORDER queryname \
     -RESTORE_ORIGINAL_QUALITIES true \
     -REMOVE_DUPLICATE_INFORMATION true \
     -REMOVE_ALIGNMENT_INFORMATION true \
     -VALIDATION_STRINGENCY LENIENT
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




# Mark duplicate reads to avoid counting non-independent observations
task MarkDuplicates {
  input {
    File input_bam
    String output_bam_basename
    String metrics_filename
#    Float total_input_size
    Int compression_level
    String? picard_jar = "/usr/local/jars/picard.jar"

    # The program default for READ_NAME_REGEX is appropriate in nearly every case.
    # Sometimes we wish to supply "null" in order to turn off optical duplicate detection
    # This can be desirable if you don't mind the estimated library size being wrong and optical duplicate detection is taking >7 days and failing
    String? read_name_regex
    Int memory_multiplier = 1
    Int additional_disk = 20

    Float? sorting_collection_size_ratio
  }

  # The merged bam will be smaller than the sum of the parts so we need to account for the unmerged inputs and the merged output.
  # Mark Duplicates takes in as input readgroup bams and outputs a slightly smaller regated bam. Giving .25 as wiggleroom
  Float md_disk_multiplier = 3
#  Int disk_size = ceil(md_disk_multiplier * total_input_size) + additional_disk

  Float memory_size = 7.5 * memory_multiplier
  Int java_memory_size = (ceil(memory_size) - 2)

  # Task is assuming query-sorted input so that the Secondary and Supplementary reads get marked correctly
  # This works because the output of BWA is query-grouped and therefore, so is the output of MergeBamAlignment.
  # While query-grouped isn't actually query-sorted, it's good enough for MarkDuplicates with ASSUME_SORT_ORDER="queryname"

  command {
    java -Dsamjdk.compression_level=~{compression_level} -Xms~{java_memory_size}g -jar ~{picard_jar} \
      MarkDuplicates \
      INPUT=~{input_bam} \
      OUTPUT=~{output_bam_basename}.bam \
      METRICS_FILE=~{metrics_filename} \
      VALIDATION_STRINGENCY=SILENT \
      ~{"READ_NAME_REGEX=" + read_name_regex} \
      ~{"SORTING_COLLECTION_SIZE_RATIO=" + sorting_collection_size_ratio} \
      OPTICAL_DUPLICATE_PIXEL_DISTANCE=2500 \
      ASSUME_SORT_ORDER="queryname" \
      CLEAR_DT="false" \
      ADD_PG_TAG_TO_READS=false
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: java_memory_size + 1000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
    File duplicate_metrics = "~{metrics_filename}"
  }
}

# Mark duplicate reads to avoid counting non-independent observations
task MergeAndMarkDuplicates {
  input {
    Array[File] input_bams
    String output_bam_basename
    String metrics_filename
#    Float total_input_size
    Int compression_level
    String? picard_jar = "/usr/local/jars/picard.jar"

    # The program default for READ_NAME_REGEX is appropriate in nearly every case.
    # Sometimes we wish to supply "null" in order to turn off optical duplicate detection
    # This can be desirable if you don't mind the estimated library size being wrong and optical duplicate detection is taking >7 days and failing
    String? read_name_regex
    Int memory_multiplier = 1
    Int additional_disk = 20

    Float? sorting_collection_size_ratio
  }

  # The merged bam will be smaller than the sum of the parts so we need to account for the unmerged inputs and the merged output.
  # Mark Duplicates takes in as input readgroup bams and outputs a slightly smaller aggregated bam. Giving .25 as wiggleroom
  Float md_disk_multiplier = 3
#  Int disk_size = ceil(md_disk_multiplier * total_input_size) + additional_disk

  Float memory_size = 7.5 * memory_multiplier
  Int java_memory_size = (ceil(memory_size) - 2)

  # Task is assuming query-sorted input so that the Secondary and Supplementary reads get marked correctly
  # This works because the output of BWA is query-grouped and therefore, so is the output of MergeBamAlignment.
  # While query-grouped isn't actually query-sorted, it's good enough for MarkDuplicates with ASSUME_SORT_ORDER="queryname"

  command {
    mkdir qc 
    java -Dsamjdk.compression_level=~{compression_level} -Xms~{java_memory_size}g -jar ~{picard_jar} \
      MarkDuplicates \
      INPUT=~{sep=' INPUT=' input_bams} \
      OUTPUT=~{output_bam_basename}.bam \
      METRICS_FILE=qc/~{metrics_filename} \
      VALIDATION_STRINGENCY=SILENT \
      ~{"READ_NAME_REGEX=" + read_name_regex} \
      ~{"SORTING_COLLECTION_SIZE_RATIO=" + sorting_collection_size_ratio} \
      OPTICAL_DUPLICATE_PIXEL_DISTANCE=2500 \
      ASSUME_SORT_ORDER="queryname" \
      CLEAR_DT="false" \
      ADD_PG_TAG_TO_READS=false
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: java_memory_size+1000
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
    File duplicate_metrics = "qc/~{metrics_filename}"
  }
}


task MergeUnalignedBams {
  input {
    Array[File] bams
    String output_bam_basename
    Boolean? index = false
    String? samtools_cmd = "/usr/local/bin/samtools"
    
  }

    
  command {
    ~{samtools_cmd} merge -n ~{output_bam_basename} ~{sep=' ' bams}
#    if [~{index}]; then
#      /usr/local/bin/samtools index -n ~{output_bam_basename} 
  }
  output {
    File output_bam = "~{output_bam_basename}"
#    File bam_index = "~{output_bam_basename}.bai" if bam_index
  }
}


task BamAddProgramLine {
  input {
    File bamfile
    String id
    String version
    String? name
    String? command_line
    String? description
    String samtools_cmd = '/usr/local/bin/samtools'
  }

  command {
    set -e
    ~{samtools_cmd} view --no-PG -H ~{bamfile} > ~{bamfile}.header

    echo -en "@PG\tID:~{id}\tVN:~{version}" >> ~{bamfile}.header

    if [ ! -z ~{name}]
    then
      echo -en "\tPN:~{name}" >> ~{bamfile}.header
    fi
    
    if [ ! -z ~{command_line}]
    then
      echo -en "\tCL:~{command_line}" >> ~{bamfile}.header
    fi

    if [ ! -z ~{description}]
    then
      echo -en "\tDS:~{description}" >> ~{bamfile}.header
    fi

    echo  "" >> ~{bamfile}.header

    ~{samtools_cmd} reheader -P ~{bamfile}.header ~{bamfile} > ~{bamfile}.reheadered
    mv -f ~{bamfile}.reheadered ~{bamfile}

  }

  output {
    File output_bam = bamfile
  }

}


# Generate Base Quality Score Recalibration (BQSR) model
task BaseRecalibrator {
  input {
    File input_bam
    File input_bam_index
    String recalibration_report_filename
    Array[String] sequence_group_interval
    File dbsnp_vcf
    File dbsnp_vcf_index
    Array[File] known_indels_sites_vcfs
    Array[File] known_indels_sites_indices
    File ref_dict
    File ref_fasta
    File ref_fasta_index
    Int bqsr_scatter
    String gatk_docker = "us.gcr.io/broad-gatk/gatk:4.1.8.0"
    String gatk_cmd = "/usr/local/bin/gatk"
  }

  Float ref_size = size(ref_fasta, "GiB") + size(ref_fasta_index, "GiB") + size(ref_dict, "GiB")
  Float dbsnp_size = size(dbsnp_vcf, "GiB")
  Int disk_size = ceil((size(input_bam, "GiB") / bqsr_scatter) + ref_size + dbsnp_size) + 20

  parameter_meta {
    input_bam: {
      localization_optional: true
    }
  }

  command {
    ~{gatk_cmd} --java-options -Xms5g \
      BaseRecalibrator \
      -R ~{ref_fasta} \
      -I ~{input_bam} \
      --use-original-qualities \
      -O ~{recalibration_report_filename} \
      --known-sites ~{dbsnp_vcf} \
      --known-sites ~{sep=" -known-sites " known_indels_sites_vcfs} \
      -L ~{sep=" -L " sequence_group_interval}
  }
  runtime {
    #docker: gatk_docker
    memory: 6000
  }
  output {
    File recalibration_report = "~{recalibration_report_filename}"
  }
}



 
# Apply Base Quality Score Recalibration (BQSR) model
task ApplyBQSR {
  input {
    File input_bam
    File input_bam_index
    String output_bam_basename
    File recalibration_report
    Array[String] sequence_group_interval
    File ref_dict
    File ref_fasta
    File ref_fasta_index
    Int compression_level
    Int bqsr_scatter
    Int memory_multiplier = 1
    Int additional_disk = 20
    Boolean bin_base_qualities = true
    Boolean somatic = false
    String gatk_cmd = '/usr/local/bin/gatk'
  }

  Float ref_size = size(ref_fasta, "GiB") + size(ref_fasta_index, "GiB") + size(ref_dict, "GiB")
  Int disk_size = ceil((size(input_bam, "GiB") * 3 / bqsr_scatter) + ref_size) + additional_disk

  Int memory_size = ceil(3500 * memory_multiplier)

  Boolean bin_somatic_base_qualities = bin_base_qualities && somatic

  parameter_meta {
    input_bam: {
      localization_optional: true
    }
  }

  command {
    ~{gatk_cmd} --java-options "-Dsamjdk.compression_level=~{compression_level} -Xms3000m" \
      ApplyBQSR \
      --create-output-bam-md5 \
      --add-output-sam-program-record \
      -R ~{ref_fasta} \
      -I ~{input_bam} \
      --use-original-qualities \
      -O ~{output_bam_basename}.bam \
      -bqsr ~{recalibration_report} \
      ~{true='--static-quantized-quals 10' false='' bin_base_qualities} \
      ~{true='--static-quantized-quals 20' false='' bin_base_qualities} \
      ~{true='--static-quantized-quals 30' false='' bin_base_qualities} \
      ~{true='--static-quantized-quals 40' false='' bin_somatic_base_qualities} \
      ~{true='--static-quantized-quals 50' false='' bin_somatic_base_qualities} \
      -L ~{sep=" -L " sequence_group_interval}
  }
  runtime {
    #docker: gatk_docker
    memory: 4000
  }
  output {
    File recalibrated_bam = "~{output_bam_basename}.bam"
    File recalibrated_bam_checksum = "~{output_bam_basename}.bam.md5"
  }
}

# Combine multiple recalibration tables from scattered BaseRecalibrator runs
task GatherBqsrReports {
  input {
    Array[File] input_bqsr_reports
    String output_report_filename
    String gatk_docker = "us.gcr.io/broad-gatk/gatk:4.1.8.0"
    String gatk_cmd = '/usr/local/bin/gatk'
  }

  command {
    ~{gatk_cmd} --java-options "-Xms3000m" \
      GatherBQSRReports \
      -I ~{sep=' -I ' input_bqsr_reports} \
      -O ~{output_report_filename}
    }
  runtime {
    #docker: gatk_docker
    memory: 3500
  }
  output {
    File output_bqsr_report = "~{output_report_filename}"
  }
}

# Combine multiple *sorted* BAM files
task GatherSortedBamFiles {
  input {
    Array[File] input_bams
    String output_bam_basename
    Float total_input_size
    Int compression_level
    String? picard_jar = "/usr/local/jars/picard.jar"
  }

  # Multiply the input bam size by two to account for the input and output
  Int disk_size = ceil(2 * total_input_size) + 20

  command {
    java -Dsamjdk.compression_level=~{compression_level} -Xms2000m -jar ~{picard_jar} \
      GatherBamFiles \
      INPUT=~{sep=' INPUT=' input_bams} \
      OUTPUT=~{output_bam_basename}.bam \
      CREATE_INDEX=true \
      CREATE_MD5_FILE=true
    }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 3000
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
    File output_bam_index = "~{output_bam_basename}.bai"
    File output_bam_md5 = "~{output_bam_basename}.bam.md5"
  }
}

# Combine multiple *unsorted* BAM files
# Note that if/when WDL supports optional outputs, we should merge this task with the sorted version
task GatherUnsortedBamFiles {
  input {
    Array[File] input_bams
    String output_bam_basename
    Float total_input_size
    Int compression_level
    String? picard_jar = "/usr/local/jars/picard.jar"
  }

  # Multiply the input bam size by two to account for the input and output
  Int disk_size = ceil(2 * total_input_size) + 20

  command {
    java -Dsamjdk.compression_level=~{compression_level} -Xms2000m -jar ~{picard_jar}   \
      GatherBamFiles \
      INPUT=~{sep=' INPUT=' input_bams} \
      OUTPUT=~{output_bam_basename}.bam \
      CREATE_INDEX=false \
      CREATE_MD5_FILE=false
    }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/picard-cloud:2.23.8"
    memory: 3000
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
  }
}

task GenerateSubsettedContaminationResources {
  input {
    String bait_set_name
    File target_interval_list
    File contamination_sites_ud
    File contamination_sites_bed
    File contamination_sites_mu
  }

  String output_ud = bait_set_name + "." + basename(contamination_sites_ud)
  String output_bed = bait_set_name + "." + basename(contamination_sites_bed)
  String output_mu = bait_set_name + "." + basename(contamination_sites_mu)
  String target_overlap_counts = "target_overlap_counts.txt"

  command <<<
    set -e -o pipefail

    grep -vE "^@" ~{target_interval_list} |
       awk -v OFS='\t' '$2=$2-1' |
       /app/bedtools intersect -c -a ~{contamination_sites_bed} -b - |
       cut -f6 > ~{target_overlap_counts}

    function restrict_to_overlaps() {
        # print lines from whole-genome file from loci with non-zero overlap
        # with target intervals
        WGS_FILE=$1
        EXOME_FILE=$2
        paste ~{target_overlap_counts} $WGS_FILE |
            grep -Ev "^0" |
            cut -f 2- > $EXOME_FILE
        echo "Generated $EXOME_FILE"
    }

    restrict_to_overlaps ~{contamination_sites_ud} ~{output_ud}
    restrict_to_overlaps ~{contamination_sites_bed} ~{output_bed}
    restrict_to_overlaps ~{contamination_sites_mu} ~{output_mu}

  >>>
  runtime {
    memory: 3500
  }
  output {
    File subsetted_contamination_ud = output_ud
    File subsetted_contamination_bed = output_bed
    File subsetted_contamination_mu = output_mu
  }
}


task HaplotypeCaller {
  input {
    File input_bam
    File input_bam_index
    File interval_list
    String vcf_basename
    File ref_dict
    File ref_fasta
    File ref_fasta_index
    Float? contamination
    Boolean make_gvcf
    Int hc_scatter = 199
    String gatk_cmd = "/usr/local/bin/gatk"
  }

  String output_suffix = if make_gvcf then ".g.vcf.gz" else ".vcf.gz"
  String output_file_name = vcf_basename + output_suffix

  Float ref_size = size(ref_fasta, "GiB") + size(ref_fasta_index, "GiB") + size(ref_dict, "GiB")

#  String bamout_arg = if make_bamout then "-bamout ~{vcf_basename}.bamout.bam" else ""

  parameter_meta {
    input_bam: {
      localization_optional: true
    }
  }

  command <<<
    set -e
    ~{gatk_cmd} --java-options "-Xms5500m " \
      HaplotypeCaller \
      -R ~{ref_fasta} \
      -I ~{input_bam} \
      -L ~{interval_list} \
      -O ~{output_file_name} \
      -contamination ~{default=0 contamination} \
      -G StandardAnnotation -G StandardHCAnnotation ~{true="-G AS_StandardAnnotation" false="" make_gvcf} \
      -GQB 10 -GQB 20 -GQB 30 -GQB 40 -GQB 50 -GQB 60 -GQB 70 -GQB 80 -GQB 90 \
      ~{true="-ERC GVCF" false="" make_gvcf} \
      --add-output-vcf-command-line

    # Cromwell doesn't like optional task outputs, so we have to touch this file.
    touch ~{vcf_basename}.bamout.bam
  >>>

  runtime {
#    docker: gatk_docker
    memory: 6500
    cpus: "2"
  }

  output {
    File output_vcf = "~{output_file_name}"
    File output_vcf_index = "~{output_file_name}.tbi"
    File bamout = "~{vcf_basename}.bamout.bam"
  }
}



# Notes on the contamination estimate:
# The contamination value is read from the FREEMIX field of the selfSM file output by verifyBamId
#
# In Zamboni production, this value is stored directly in METRICS.AGGREGATION_CONTAM
#
# Contamination is also stored in GVCF_CALLING and thereby passed to HAPLOTYPE_CALLER
# But first, it is divided by an underestimation factor thusly:
#   float(FREEMIX) / ContaminationUnderestimationFactor
#     where the denominator is hardcoded in Zamboni:
#     val ContaminationUnderestimationFactor = 0.75f
#
# Here, I am handling this by returning both the original selfSM file for reporting, and the adjusted
# contamination estimate for use in variant calling
task CheckContamination {
  input {
    File input_bam
    File input_bam_index
    File contamination_sites_ud
    File contamination_sites_bed
    File contamination_sites_mu
    File ref_fasta
    File ref_fasta_index
    String output_prefix
    Float contamination_underestimation_factor
    Boolean disable_sanity_check = false
    String verifybamid_cmd = "/usr/local/bin/VerifyBamID"
  }

  Int disk_size = ceil(size(input_bam, "GiB") + size(ref_fasta, "GiB")) + 30

  command <<<
    set -e

    # creates a ~{output_prefix}.selfSM file, a TSV file with 2 rows, 19 columns.
    # First row are the keys (e.g., SEQ_SM, RG, FREEMIX), second row are the associated values
    ~{verifybamid_cmd} \
    --Verbose \
    --NumPC 4 \
    --Output ~{output_prefix} \
    --BamFile ~{input_bam} \
    --Reference ~{ref_fasta} \
    --UDPath ~{contamination_sites_ud} \
    --MeanPath ~{contamination_sites_mu} \
    --BedPath ~{contamination_sites_bed} \
    ~{true="--DisableSanityCheck" false="" disable_sanity_check} \
    1>/dev/null

    # used to read from the selfSM file and calculate contamination, which gets printed out
    python3 <<CODE
    import csv
    import sys
    with open('~{output_prefix}.selfSM') as selfSM:
      reader = csv.DictReader(selfSM, delimiter='\t')
      i = 0
      for row in reader:
        if float(row["FREELK0"])==0 and float(row["FREELK1"])==0:
          # a zero value for the likelihoods implies no data. This usually indicates a problem rather than a real event.
          # if the bam isn't really empty, this is probably due to the use of a incompatible reference build between
          # vcf and bam.
          sys.stderr.write("Found zero likelihoods. Bam is either very-very shallow, or aligned to the wrong reference (relative to the vcf).")
          sys.exit(1)
        print(float(row["FREEMIX"])/~{contamination_underestimation_factor})
        i = i + 1
        # there should be exactly one row, and if this isn't the case the format of the output is unexpectedly different
        # and the results are not reliable.
        if i != 1:
          sys.stderr.write("Found %d rows in .selfSM file. Was expecting exactly 1. This is an error"%(i))
          sys.exit(2)
    CODE
  >>>
  runtime {
    memory: 7500
    cpus: 2
  }
  output {
    File selfSM = "~{output_prefix}.selfSM"
    Float contamination = read_float(stdout())
  }
}
