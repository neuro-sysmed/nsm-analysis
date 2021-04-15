#!/usr/bin/env python3

import kbr.run_utils as run_utils
import filecmp
import os 


def test_version_file_ops():
    cmd = "cromwell run utils_test.wdl"
    p = run_utils.launch_cmd(cmd)
    assert p.p_status == 0, "Cromwell call failed"

    assert filecmp.cmp('/etc/passwd', '/tmp/passwd.backup')
    assert os.path.isfile('/tmp/version'), "version not written to file"



