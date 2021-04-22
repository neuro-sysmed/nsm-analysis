#!/usr/bin/env python3

import kbr.run_utils as run_utils
import kbr.file_utils as file_utils
import filecmp
import os 


def test_version_file_ops():
    cmd = "cromwell run utils_test.wdl"
    p = run_utils.launch_cmd(cmd)
    assert p.p_status == 0, "Cromwell call failed"

    assert filecmp.cmp('/etc/passwd', '/tmp/passwd.backup')
    assert os.path.isfile('/tmp/version'), "version not written to file"

    total_reads = file_utils.read('/tmp/read_counts.txt')
    
    assert "233800\n" == total_reads


