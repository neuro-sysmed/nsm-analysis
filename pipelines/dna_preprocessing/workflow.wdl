version 1.0
#import "../../vars/global.wdl" as global

import "../../tasks/Alignment.wdl" as Alignment
#import "../../dna_seq/DNASeqStructs.wdl" as Structs


workflow DNAPreprocessing {





#  call global
 call Alignment.BwaMem as BwaMem {
     input:
        input_bam = 'tyt'
 }
    

 output {
    String version = BwaMem.bwa_version

 }

}



