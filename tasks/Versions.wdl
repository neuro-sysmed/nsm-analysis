version 1.0

workflow Versions {
   input {
      String? image
      String? version_file
      String? bcftools_module
      String? bedtools_module
      String? gatk_module
      String? picard_module
      String? salmon_module
      String? samtools_module
      String? star_module
      String? bwa_module
      String? version_file
   }


    call Bwa as Bwa {
        input:
          bwa_module = bwa_module
    }

    call Samtools as Samtools {
        input:
          samtools_module = samtools_module
    }

    call Picard as Picard {
        input:
          picard_module = picard_module
    }

    call Gatk as Gatk {
        input:
          gatk_module = gatk_module
    }

    call Bcftools as Bcftools {
        input:
          bcftools_module = bcftools_module
    }

    call Bedtools as Bedtools {
        input:
          bedtools_module = bedtools_module
    }

    call Star as Star {
        input:
          star_module = star_module
    }


    call Salmon as Salmon {
        input:
          salmon_module = salmon_module
    }

    call Image as Image {
        input:
          image = image
    }

#    call Package as Package {
#        input:
#          version_file = version_file
#    }

#    call Singularity as Singularity

    output {
#        String package  = Package.version
        String package  = "Package.version"
        String bwa      = Bwa.version
        String samtools = Samtools.version
        String picard   = Picard.version
        String gatk     = Gatk.version
        String bcftools = Bcftools.version
        String bedtools = Bedtools.version
        String star     = Star.version        
#        String singularity = Singularity.version
        String singularity = "Meh"
        String image    = Image.version
        String salmon   = Salmon.version
    }
}


task Package {
    input {
      String version_file = "/usr/local/lib/nsm-analysis/version.json"
    }

    command {
        RepoVersion=$(jq -r 'if .dev then 
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) +"-dev"+(.dev|tostring) 
            elif .rc then
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) +"-rc"+(.rc|tostring) 
            else
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) end' \
            < ~{version_file})

        echo "$RepoVersion"
    }

    runtime {
        backend: "nsm-local"
    }

    output {
        String version = read_string(stdout())
    }

    parameter_meta {
      # inputs
      version_file: {description: "version file for the repo", category: "optional"}
    }
}


task Image {
    input {
      String image = "/usr/local/images/nsm-tools.sif"
    }

    command {
        image_version=$(singularity inspect ~{image} 2>&1 | \
        grep -e 'org.label-schema.usage.singularity.deffile.from' | \
        perl -pe 's/org.label-schema.usage.singularity.deffile.from: //')

        echo $image_version
    }

    runtime {
        backend: "nsm-local"
        image: "/usr/local/images/nsm-tools.sif"
    }


    output {
        String version = read_string(stdout())
    }
}

task Singularity {
    input {
      String singularity_cmd = "singularity"
    }

    command {
        singularity_version=$(~{singularity_cmd} --version 2>&1 | \
            perl -pe 's/.*version //')

        echo $singularity_version
    }

    runtime {
        backend: "nsm-local"
#        image: "/data/analysis/nsm-tools.sif"
    }

    output {
        String version = read_string(stdout())
    }
}


task Salmon {
    input {
      String salmon_cmd = 'salmon'
      String? salmon_module
    }

    command {
        if [ -z ${salmon_module+"x"} ]; then
            module load ~{salmon_module}
        fi

        salmon_version=$(~{salmon_cmd} --version 2>&1 | \
            perl -pe 's/^salmon //')

        echo $salmon_version
    }

    runtime {
#        backend: "nsm-local"
    }

    output {
        String version = read_string(stdout())
    }
}



task Bwa {
    input {
        String bwa_cmd = 'bwa'
        String? bwa_module
    }

    command {
        if [ -z ${bwa_module+"x"} ]; then
            module load ~{bwa_module}
        fi

        bwa_version=$(~{bwa_cmd} 2>&1 | \
            grep -e '^Version' | \
            sed 's/Version: //')

        echo $bwa_version
    }

    output {
        String version = read_string(stdout())
    }
}


task Samtools {
    input {
        String samtools_cmd = 'samtools'
        String? samtools_module
    }

    command {
        if [ -z ${samtools_module+"x"} ]; then
            module load ~{samtools_module}
        fi

        samtools_version=$(~{samtools_cmd} 2>&1  | \
            egrep Version | \
            perl -pe 's/Version: (.*?) .*/$1/')

        echo $samtools_version
    }

    output {
        String version = read_string(stdout())
    }
}


task Picard {
    input {
        String PICARD_JAR = '/usr/local/jars/picard.jar '
        String? picard_module
    }

    command {
        if [ -z ${picard_module+"x"} ]; then
            module load ~{picard_module}
        fi

        picard_version=$(java -jar ~{PICARD_JAR} MarkDuplicates --version 2>&1 | \
            egrep ^Version | \
            perl -pe 's/Version://')

        echo $picard_version
    }

    output {
        String version = read_string(stdout())
    }
}

task Gatk {
    input {
        String gatk_cmd = 'gatk'
        String? gatk_module
    }

    command {
        if [ -z ${gatk_module+"x"} ]; then
            module load ~{gatk_module}
        fi

        gatk_version=$(~{gatk_cmd} --version | \
             egrep "The Genome Analysis Toolkit" | \
             perl -pe 's/.* v//')

        echo $gatk_version
    }

    output {
        String version = read_string(stdout())
    }
}

task Star {
    input {
        String star_cmd = 'STAR'
        String? star_module
    }

    command {
        if [ -z ${star_module+"x"} ]; then
            module load ~{star_module}
        fi

         star_version=$(~{star_cmd} | \
             egrep version | \
             perl -pe 's/.* version=//')

        echo $star_version
    }

    output {
        String version = read_string(stdout())
    }
}

task Bcftools {
    input {
        String bcftools_cmd = 'bcftools'
        String? bcftools_module
    }

#    String bcftools_cmd = 'singularity exec /home/brugger/projects/kbr-tools/nsm-tools.sif /usr/local/bin/bcftools'

    command {
        if [ -z ${bcftools_module+"x"} ]; then
            module load ~{bcftools_module}
        fi
        bcftools_version=$(~{bcftools_cmd} 2>&1 | \
             egrep Vers | \
             perl -pe 's/Version: (.*?) .*/$1/')

        echo $bcftools_version
    }

    output {
        String version = read_string(stdout())
    }
}


task Bedtools {
    input {
        String bedtools_cmd = '/usr/local/bin/bedtools'
        String? bedtools_module
    }

#    String bcftools_cmd = 'singularity exec /home/brugger/projects/kbr-tools/nsm-tools.sif /usr/local/bin/bcftools'

    command {
        if [ -z ${bedtools_module+"x"} ]; then
             module load ~{bedtools_module}
        fi

        bedtools_version=$(~{bedtools_cmd} --version  | \
             perl -pe 's/^bedtools //')

        echo $bedtools_version
    }

    output {
        String version = read_string(stdout())
    }
}
