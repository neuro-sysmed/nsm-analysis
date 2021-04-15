version 1.0 

import "../../tasks/Utils.wdl" as Utils

workflow UtilsTest {

    call Utils.Version as Version {
        input:
            version_file = "../../version.json"
    }


    call Utils.WriteStringsToFile as Tofile {
        input:
          strings = [Version.version],
          outfile = "/tmp/version"
    }

    call Utils.FileCopy as FileCopy {
        input:
          infile = "/etc/passwd",
          outfile = "/tmp/passwd"
    }


    call Utils.FileRename as FileRename {
        input:
          infile = FileCopy.outfile,
          outfile = "/tmp/passwd.backup"
    }


}