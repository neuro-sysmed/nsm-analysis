version 1.0

# Read unmapped BAM, convert on-the-fly to FASTQ and stream to BWA MEM for alignment, then stream to MergeBamAlignment

task BwaMem {
  input {
    String input_bam
  }

command <<<


    # This is done before "set -o pipefail" because "bwa" will have a rc=1 and we don't want to allow rc=1 to succeed
    # because the sed may also fail with that error and that is something we actually want to fail on.
    BWA_VERSION=$(bwa 2>&1 | \
    grep -e '^Version' | \
    sed 's/Version: //')

    set -o pipefail
    set -e

    if [ -z ${BWA_VERSION} ]; then
        exit 1;
    fi

    echo "${BWA_VERSION}"
>>>

  output {
     String bwa_version = stdout()
  }
}