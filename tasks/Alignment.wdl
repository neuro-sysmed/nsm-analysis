version 1.0

# Read unmapped BAM, convert on-the-fly to FASTQ and stream to BWA MEM for alignment, then stream to MergeBamAlignment

#import "../vars/global.wdl" as global

import "../structs/DNASeqStructs.wdl"


task BwaMem {
# Read unmapped BAM, convert on-the-fly to FASTQ and stream to BWA MEM for alignment, then stream to MergeBamAlignment
  input {
    File input_bam
    String? bwa_cmd = "/usr/local/bin/bwa"
    String? picard_jar = "/usr/local/jars/picard.jar"
    String bam_basename

    ReferenceFasta reference_fasta

    Int compression_level
    Boolean hard_clip_reads = false
  }

  Float unmapped_bam_size = size(input_bam, "GiB")
  Float ref_size = size(reference_fasta.ref_fasta, "GiB") + size(reference_fasta.ref_fasta_index, "GiB") + size(reference_fasta.ref_dict, "GiB")
  Float bwa_ref_size = ref_size + size(reference_fasta.ref_amb, "GiB") + size(reference_fasta.ref_ann, "GiB") + size(reference_fasta.ref_bwt, "GiB") + size(reference_fasta.ref_pac, "GiB") + size(reference_fasta.ref_sa, "GiB")
  # Sometimes the output is larger than the input, or a task can spill to disk.
  # In these cases we need to account for the input (1) and the output (1.5) or the input(1), the output(1), and spillage (.5).
  Float disk_multiplier = 2.5
  Int disk_size = ceil(unmapped_bam_size + bwa_ref_size + (disk_multiplier * unmapped_bam_size) + 20)

  String bwa_commandline = " mem -K 100000000 -p -v 3 -t 3 -Y $bash_ref_fasta"

  command <<<

    bash_ref_fasta=~{reference_fasta.ref_fasta}

    # This is done before "set -o pipefail" because "bwa" will have a rc=1 and we don't want to allow rc=1 to succeed
    # because the sed may also fail with that error and that is something we actually want to fail on.
    BWA_VERSION=$(~{bwa_cmd} 2>&1 | \
    grep -e '^Version' | \
    sed 's/Version: //')

    set -o pipefail
    set -e

    if [ -z ${BWA_VERSION} ]; then
        exit 1;
    fi

    # set the bash variable needed for the command-line
    bash_ref_fasta=~{reference_fasta.ref_fasta}
    # if reference_fasta.ref_alt has data in it,
    if [ -s ~{reference_fasta.ref_fasta} ]; then
      java -Xms1000m -Xmx1000m -jar ~{picard_jar} \
        SamToFastq \
        INPUT=~{input_bam} \
        FASTQ=/dev/stdout \
        INTERLEAVE=true \
        NON_PF=true | \
      ~{bwa_cmd} ~{bwa_commandline} /dev/stdin - 2> >(tee ~{bam_basename}.bwa.stderr.log >&2) | \
      java -Dsamjdk.compression_level=~{compression_level} -Xms1000m -Xmx1000m -jar ~{picard_jar} \
        MergeBamAlignment \
        VALIDATION_STRINGENCY=SILENT \
        EXPECTED_ORIENTATIONS=FR \
        ATTRIBUTES_TO_RETAIN=X0 \
        ATTRIBUTES_TO_REMOVE=NM \
        ATTRIBUTES_TO_REMOVE=MD \
        ALIGNED_BAM=/dev/stdin \
        UNMAPPED_BAM=~{input_bam} \
        OUTPUT=~{bam_basename}.bam \
        REFERENCE_SEQUENCE=~{reference_fasta.ref_fasta} \
        PAIRED_RUN=true \
        SORT_ORDER="unsorted" \
        IS_BISULFITE_SEQUENCE=false \
        ALIGNED_READS_ONLY=false \
        CLIP_ADAPTERS=false \
        ~{true='CLIP_OVERLAPPING_READS=true' false="" hard_clip_reads} \
        ~{true='CLIP_OVERLAPPING_READS_OPERATOR=H' false="" hard_clip_reads} \
        MAX_RECORDS_IN_RAM=2000000 \
        ADD_MATE_CIGAR=true \
        MAX_INSERTIONS_OR_DELETIONS=-1 \
        PRIMARY_ALIGNMENT_STRATEGY=MostDistant \
        PROGRAM_RECORD_ID="bwamem" \
        PROGRAM_GROUP_VERSION="${BWA_VERSION}" \
        PROGRAM_GROUP_COMMAND_LINE="bwa ~{bwa_commandline}" \
        PROGRAM_GROUP_NAME="bwamem" \
        UNMAPPED_READ_STRATEGY=COPY_TO_TAG \
        ALIGNER_PROPER_PAIR_FLAGS=true \
        UNMAP_CONTAMINANT_READS=true \
        ADD_PG_TAG_TO_READS=false

 #     grep -m1 "read .* ALT contigs" ~{bam_basename}.bwa.stderr.log | \
 #     grep -v "read 0 ALT contigs"

    # else reference_fasta.ref_alt is empty or could not be found
    else
      exit 1;
    fi
  >>>
  runtime {
#    docker: "bruggerk/nsm-tools:latest"
#    memory: "14 GiB"
    cpus: 4
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File aligned_bam = "~{bam_basename}.bam"
    File bwa_stderr_log = "~{bam_basename}.bwa.stderr.log"
  }
}

task Star {
  input {
      String base_file_name
      File fwd_reads
      File rev_reads
      File gtf
      String genome_dir
      String? star_cmd = "/usr/local/bin/STAR"
      Int? threads = 4
  }

  command {
    ~{star_cmd} --outSAMattributes All --outSAMtype BAM SortedByCoordinate \
       --quantMode GeneCounts \
       --readFilesCommand zcat \
       --runThreadN ~{threads} \
       --sjdbGTFfile ~{gtf} \
       --outReadsUnmapped Fastx \
       --outMultimapperOrder Random \
       --outWigType wiggle \
       --genomeDir ~{genome_dir} \
       --readFilesIn ~{fwd_reads} ~{rev_reads} \
       --outFileNamePrefix \
       ~{base_file_name}
  }

  output {
    File bam_file = "~{base_file_name}.bam"
  }
}

task Salmon {
  input {
      String sample_name
      File fwd_reads
      File? rev_reads
      String reference_dir
      Int threads = 4
  }

  command {

    if [  -z "~{rev_reads}" ]; then
        salmon quant -i ~{reference_dir} -l A -1 ~{fwd_reads} \
         -p ~{threads} --validateMappings -o ~{sample_name}
    else
        salmon quant -i ~{reference_dir} -l A -1 ~{fwd_reads} -2 ~{rev_reads} \
         -p ~{threads} --validateMappings -o ~{sample_name}
    fi


  }

  output {
    File flenDist = "~{sample_name}/libParams/flenDist.txt"
    File quant = "~{sample_name}/quant.sf"
    File cmdInfo = "~{sample_name}/cmd_info.json"
    File libFormatCounts = "~{sample_name}/lib_format_counts.json"
    File log = "~{sample_name}/logs/salmon_quant.log"
    File ambigInfo = "~{sample_name}/aux_info/ambig_info.tsv"
    File fld= "~{sample_name}/aux_info/fld.gz"
    File obsBias = "~{sample_name}/aux_info/observed_bias.gz"
    File expBias = "~{sample_name}/aux_info/expected_bias.gz"
    File obsBias3p = "~{sample_name}/aux_info/observed_bias_3p.gz"
    File metaInfo = "~{sample_name}/aux_info/meta_info.json"
  }
}
