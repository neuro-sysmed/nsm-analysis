version 1.0


task Version {
    input {
      String version_file = "../version.json"
    }
  # returns null for unset keys
    Map[String, String?] version_map = read_json(version_file)

    String version_str = if defined(version_map['dev']) 
            then "~{version_map['major']}.~{version_map['minor']}.~{version_map['patch']}-dev~{version_map['dev']}" 
            else "~{version_map['major']}.~{version_map['minor']}.~{version_map['patch']}"

    command {
    }


    output {
        String version = version_str
    }

    parameter_meta {
      # inputs
      version_file: {description: "version file for the repo", category: "optional"}
    }
}

task version_jq {
    # have be replaced with a read_json call
  input {
    String version_file = "../version.json"
  }


  command <<<
    RepoVersion=$(jq 'if .dev then 
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) +"-"+(.dev|tostring) 
            else 
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) end' \
            < ~{version_file} )


        echo "${RepoVersion}"

  >>>

  output {
    String version = stdout()
  }
}

task FileCopy {
  input {
    String infile
    String outfile
  }


  command {
    cp "~{infile}" "~{outfile}"
  }

  output {
    File outfile = "~{outfile}"
  }

}


task Fail {

  command {
    set -e
    python3   -c 'import sys; sys.exit(10)'
  }

}

task FileRename {
  input {
    String infile
    String outfile
  }

  command {
    mv "~{infile}" "~{outfile}"
  }

  output {
    File outfile = outfile
  }

}

task WriteStringsToFile {
  input {
    Array[String] strings
    String outfile
  }

  command {
    cp ${write_lines( strings )} ~{outfile}
  }

  runtime {
      backend: "nsm-local"
  }


  output {
    File outfile = outfile
  }
}


task WriteMapToFile {
  # map:: Map[String, String] map = {"key1": "value1", "key2": "value2"}
  input {
    Map[String,String] map
    String outfile
  }

  command {
    cp ${write_map( map )} ~{outfile}

  }

  output {
    File outfile = outfile
  }
}

task WriteJsonToFile {
  # map:: Map[String, String] map = {"key1": "value1", "key2": "value2"}
  input {
    Object data
    String outfile
  }

  command {
    cp ${write_json( data )} ~{outfile}

  }

  output {
    File outfile = outfile
  }
}


task TotalReads {
  input {
    Array[File] QualityYieldMetricsFiles
  }

  command <<<
    # exit on first error
    set -e 

    egrep -hA1 "^TOTAL" "~{sep='" "' QualityYieldMetricsFiles}"  | egrep -v "TOTAL|-" | awk '{$s+=$1} END{ print $s}'

  >>>

  output {
    Int total_reads = read_int(stdout())
  }

}

# Generate sets of intervals for scatter-gathering over chromosomes
task CreateSequenceGroupingTSV {
  input {
    File ref_dict
  }
  # Use python to create the Sequencing Groupings used for BQSR and PrintReads Scatter.
  # It outputs to stdout where it is parsed into a wdl Array[Array[String]]
  # e.g. [["1"], ["2"], ["3", "4"], ["5"], ["6", "7", "8"]]
  command <<<
    python3 <<CODE
    with open("~{ref_dict}", "r") as ref_dict_file:
        sequence_tuple_list = []
        longest_sequence = 0
        for line in ref_dict_file:
            if line.startswith("@SQ"):
                line_split = line.split("\t")
                # (Sequence_Name, Sequence_Length)
                sequence_tuple_list.append((line_split[1].split("SN:")[1], int(line_split[2].split("LN:")[1])))
        longest_sequence = sorted(sequence_tuple_list, key=lambda x: x[1], reverse=True)[0][1]
    # We are adding this to the intervals because hg38 has contigs named with embedded colons and a bug in GATK strips off
    # the last element after a :, so we add this as a sacrificial element.
    hg38_protection_tag = ":1+"
    # initialize the tsv string with the first sequence
    tsv_string = sequence_tuple_list[0][0] + hg38_protection_tag
    temp_size = sequence_tuple_list[0][1]
    for sequence_tuple in sequence_tuple_list[1:]:
        if temp_size + sequence_tuple[1] <= longest_sequence:
            temp_size += sequence_tuple[1]
            tsv_string += "\t" + sequence_tuple[0] + hg38_protection_tag
        else:
            tsv_string += "\n" + sequence_tuple[0] + hg38_protection_tag
            temp_size = sequence_tuple[1]
    # add the unmapped sequences as a separate line to ensure that they are recalibrated as well
    with open("sequence_grouping.txt","w") as tsv_file:
      tsv_file.write(tsv_string)
      tsv_file.close()

    tsv_string += '\n' + "unmapped"

    with open("sequence_grouping_with_unmapped.txt","w") as tsv_file_with_unmapped:
      tsv_file_with_unmapped.write(tsv_string)
      tsv_file_with_unmapped.close()
    CODE
  >>>
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/python:2.7"
    memory: 2000
  }
  output {
    Array[Array[String]] sequence_grouping = read_tsv("sequence_grouping.txt")
    Array[Array[String]] sequence_grouping_with_unmapped = read_tsv("sequence_grouping_with_unmapped.txt")
  }
}



# This task calls picard's IntervalListTools to scatter the input interval list into scatter_count sub interval lists
# Note that the number of sub interval lists may not be exactly equal to scatter_count.  There may be slightly more or less.
# Thus we have the block of python to count the number of generated sub interval lists.
task ScatterIntervalList {
  input {
    File interval_list
    Int scatter_count
    Int break_bands_at_multiples_of
    String picard_jar = "/usr/local/jars/picard.jar"
  }

  command <<<
    set -e
    mkdir -p out
    java -Xms1g -jar ~{picard_jar} \
      IntervalListTools \
      SCATTER_COUNT=~{scatter_count} \
      SUBDIVISION_MODE=BALANCING_WITHOUT_INTERVAL_SUBDIVISION_WITH_OVERFLOW \
      UNIQUE=true \
      SORT=true \
      BREAK_BANDS_AT_MULTIPLES_OF=~{break_bands_at_multiples_of} \
      INPUT=~{interval_list} \
      OUTPUT=out

    python3 <<CODE
    import glob, os
    # Works around a JES limitation where multiples files with the same name overwrite each other when globbed
    intervals = sorted(glob.glob("out/*/*.interval_list"))
    for i, interval in enumerate(intervals):
      (directory, filename) = os.path.split(interval)
      newName = os.path.join(directory, str(i + 1) + filename)
      os.rename(interval, newName)
    print(len(intervals))
    CODE
  >>>
  output {
    Array[File] out = glob("out/*/*.interval_list")
    Int interval_count = read_int(stdout())
  }
  runtime {
#    docker: "us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.7-1603303710"
    memory: 2000
  }
}


workflow Sleep {
  input {
    Int timeout = 60
    String? linker
  }

  call SleepTask {
    input:
      timeout = timeout
  }
}

task SleepTask {
  input {
    Int timeout = 60
  }

  command {
    sleep ~{timeout}
  }


}