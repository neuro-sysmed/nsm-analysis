version 1.0 

import "../../structs/DNASeqStructs.wdl" as Structs
import "../../tasks/BamUtils.wdl" as BamUtils
import "../../tasks/Versions.wdl" as Versions
import "../../tasks/Alignment.wdl" as Alignment

workflow BwaMemTest {

    input {
        DNASeqSingleSampleReferences references
    }

    call Versions.Versions as Versions

    call Alignment.BwaMem as BwaMem {
        input:
            input_bam = "../../../test_data/exome.ubam",
            bam_basename = "exome.aligned.unsorted",
            reference_fasta = references.reference_fasta,
            compression_level = 5,
            hard_clip_reads = false      
    }

    call BamUtils.BamAddProgramLine as BamAddPipelineVersion {
        input:
            bamfile = BwaMem.aligned_bam,
            id = 'nsm-analysis',
            version = Versions.package
    }

    call BamUtils.BamAddProgramLine as BamAddImageVersion {
        input:
            bamfile = BamAddPipelineVersion.output_bam,
            id = 'nsm-tools-image',
            version = Versions.image
    }


}