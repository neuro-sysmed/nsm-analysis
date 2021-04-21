version 1.0

task {
    input {
        String program = 'all'
    }

    command {

        bwa_bersion=$(~{bwa_cmd} 2>&1 | \
            grep -e '^Version' | \
            sed 's/Version: //')

        samtools_version = $(samtools 2>&1  | \
            egrep Version | \
            perl -pe 's/Version: (.*?) .*/$1/')

        picard_version = $(picard MarkDuplicates --version | perl -pe 's/Version://')

        bcftools_version = $(bcftools 2>&1 | \
            egrep Vers | \
            perl -pe 's/Version: (.*?) .*/$1/')


        gatk_version = $(gatk --version | \
            egrep "The Genome Analysis Toolkit" | \
            perl -pe 's/.* v//')

        star_version = $(STAR | \
            egrep version | \
            perl -pe 's/.* version=//')

    }

    runtime {
        "image":
    }


    output {
        String bwa       = bwa_version
        String samtools  = samtools_version
        String bcftools  = bcftools_version
        String gatk      = gatk_version
        String picard    = picard_version
        String star      = star_version
    }




}