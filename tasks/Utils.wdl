version 1.0


task Version {
    # shoudld be replaced with a wf and read_json, oh well

    command <<<
        RepoVersion=$(jq 'if .dev then 
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) +"-"+(.dev|tostring) 
            else 
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) end' \
            < /home/brugger/projects/nsm/nsm-analysis/version.json )


        echo "${RepoVersion}"

    >>>

    output {
        String repo_version = stdout()
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
    String? picard_jar = "/usr/local/jars/picard.jar"
  }

  command <<<
    set -e
    mkdir out
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
    docker: "us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.7-1603303710"
    memory: "2 GiB"
  }
}
