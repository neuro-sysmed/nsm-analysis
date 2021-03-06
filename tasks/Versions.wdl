version 1.0

workflow Versions {
    call Bwa as Bwa
    call Samtools as Samtools
    call Picard as Picard
    call Gatk as Gatk
    call Bcftools as Bcftools
    call Bedtools as Bedtools
    call Star as Star
    call Package as Package
    call Singularity as Singularity
    call Salmon as Salmon
    call Image as Image

    output {
        String package  = Package.version
        String bwa      = Bwa.version
        String samtools = Samtools.version
        String picard   = Picard.version
        String gatk     = Gatk.version
        String bcftools = Bcftools.version
        String bedtools = Bedtools.version
        String star     = Star.version        
        String singularity = Singularity.version
        String image    = Image.version
        String salmon   = Salmon.version
    }
}


task Package {
    input {
      String version_file = "/usr/local/lib/nsm-analysis/version.json"
    }
  # returns null for unset keys
#    Map[String, String?] version_map = read_json(version_file)

#    String version_str = if defined(version_map['dev']) 
#            then "~{version_map['major']}.~{version_map['minor']}.~{version_map['patch']}-dev~{version_map['dev']}" 
#            else "~{version_map['major']}.~{version_map['minor']}.~{version_map['patch']}"

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
#        String version = version_str
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
      String salmon_cmd = "/usr/local/bin/salmon"
    }

    command {
        singularity_version=$(~{salmon_cmd} --version 2>&1 | \
            perl -pe 's/^salmon //')

        echo $singularity_version
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
        String bwa_cmd = '/usr/local/bin/bwa'
        String? image
    }

    command {
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
        String samtools_cmd = '/usr/local/bin/samtools'
        String? image
    }

    command {
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
        String picard_cmd = 'java -jar /usr/local/jars/picard.jar '
        String? image
    }

    command {
        picard_version=$(~{picard_cmd} MarkDuplicates --version 2>&1 | \
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
        String gatk_cmd = '/usr/local/bin/gatk'
        String? image
    }

    command {
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
        String star_cmd = '/usr/local/bin/STAR'
        String? image
    }

    command {
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
        String bcftools_cmd = '/usr/local/bin/bcftools'
        String? image
    }

#    String bcftools_cmd = 'singularity exec /home/brugger/projects/kbr-tools/nsm-tools.sif /usr/local/bin/bcftools'

    command {
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
        String? image
    }

#    String bcftools_cmd = 'singularity exec /home/brugger/projects/kbr-tools/nsm-tools.sif /usr/local/bin/bcftools'

    command {
        bedtools_version=$(~{bedtools_cmd} --version  | \
             perl -pe 's/^bedtools //')

        echo $bedtools_version
    }

    output {
        String version = read_string(stdout())
    }
}
