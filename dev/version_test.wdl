version 1.0

import "../tasks/Utils.wdl" as Utils

workflow Singularity  {

#  call Utils.Version as v
  call Utils.v2 as v {
    input:
#      version_file = "/home/brugger/projects/nsm/nsm-analysis/version.json"
  }

  output {
    String version = v.version 
  }

}

