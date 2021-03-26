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
    String output_bam_basename

    ReferenceFasta reference_fasta

    Int compression_level
    Int preemptible_tries
    Boolean hard_clip_reads = false
  }

  Float unmapped_bam_size = size(input_bam, "GiB")
  Float ref_size = size(reference_fasta.ref_fasta, "GiB") + size(reference_fasta.ref_fasta_index, "GiB") + size(reference_fasta.ref_dict, "GiB")
  Float bwa_ref_size = ref_size + size(reference_fasta.ref_amb, "GiB") + size(reference_fasta.ref_ann, "GiB") + size(reference_fasta.ref_bwt, "GiB") + size(reference_fasta.ref_pac, "GiB") + size(reference_fasta.ref_sa, "GiB")
  # Sometimes the output is larger than the input, or a task can spill to disk.
  # In these cases we need to account for the input (1) and the output (1.5) or the input(1), the output(1), and spillage (.5).
  Float disk_multiplier = 2.5
  Int disk_size = ceil(unmapped_bam_size + bwa_ref_size + (disk_multiplier * unmapped_bam_size) + 20)

  String bwa_commandline = " mem -K 100000000 -p -v 3 -t 8 -Y $bash_ref_fasta"

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
      ~{bwa_cmd} ~{bwa_commandline} /dev/stdin - 2> >(tee ~{output_bam_basename}.bwa.stderr.log >&2) | \
      java -Dsamjdk.compression_level=~{compression_level} -Xms1000m -Xmx1000m -jar ~{picard_jar} \
        MergeBamAlignment \
        VALIDATION_STRINGENCY=SILENT \
        EXPECTED_ORIENTATIONS=FR \
        ATTRIBUTES_TO_RETAIN=X0 \
        ATTRIBUTES_TO_REMOVE=NM \
        ATTRIBUTES_TO_REMOVE=MD \
        ALIGNED_BAM=/dev/stdin \
        UNMAPPED_BAM=~{input_bam} \
        OUTPUT=~{output_bam_basename}.bam \
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

 #     grep -m1 "read .* ALT contigs" ~{output_bam_basename}.bwa.stderr.log | \
 #     grep -v "read 0 ALT contigs"

    # else reference_fasta.ref_alt is empty or could not be found
    else
      exit 1;
    fi
  >>>
  runtime {
#    docker: "bruggerk/nsm-tools:latest"
#    preemptible: preemptible_tries
#    memory: "14 GiB"
#    cpu: "4"
#    disks: "local-disk " + disk_size + " HDD"
  }
  output {
    File output_aligned_bam = "~{output_bam_basename}.bam"
    File bwa_stderr_log = "~{output_bam_basename}.bwa.stderr.log"
  }
}

