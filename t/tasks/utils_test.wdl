version 1.0 

import "../../tasks/Utils.wdl" as Utils

workflow UtilsTest {

    call Utils.Version as Version {
        input:
            version_file = "../../version.json"
    }


    call Utils.WriteStringsToFile as VersionTofile {
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


    call Utils.TotalReads as TotalReads {
        input:
            QualityYieldMetricsFiles = ["../test_data/sample1.ubam.qc.quality_yield_metrics",
                                        "../test_data/sample1_1.ubam.qc.quality_yield_metrics"]
    }


    call Utils.WriteStringsToFile as TotalTofile {
        input:
          strings = [TotalReads.total_reads],
          outfile = "/tmp/read_counts.txt"
    }


    if (TotalReads.total_reads != 1) {
        call Utils.Fail as Fail
    }

}