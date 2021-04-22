version 1.0

import "../tasks/Alignment.wdl" as Alignment
import "../tasks/QC.wdl" as QC
import "../tasks/BamUtils.wdl" as BamUtils

#import "../../dna_seq/DNASeqStructs.wdl" as Structs
import "../vars/global.wdl" as global


workflow RNAPreprocessing {

   input {
      String sample_name
      String base_file_name
      File fwd_reads
      File rev_reads
      File gtf
      String genome_dir
   }


   Boolean hard_clip_reads = false

   call global.global


  # Sort aggregated+deduped BAM file and fix tags
   call BamUtils.SortSam as SortBam {
      input:
         input_bam = MarkDuplicates.output_bam,
         output_bam_basename = sample_and_unmapped_bams.base_file_name + ".aligned.duplicate_marked.sorted",
         compression_level = compression_level,
         preemptible_tries = preemptible_tries
   }

   call BamUtils.MarkDuplicates as MarkDuplicates {
      input:
         input_bam = BwaMem.output_aligned_bam,
         output_bam_basename = sample_and_unmapped_bams.base_file_name + ".aligned.unsorted.duplicates_marked",
         metrics_filename = sample_and_unmapped_bams.base_file_name + ".duplicate_metrics",
#      total_input_size = SumFloats.total_size,
         compression_level = compression_level,
         preemptible_tries = preemptible_tries
   }

   call BamUtils.SplitNCigarReads as SplitNCigarReads {
      input:
         input_bam = MarkDuplicates.bamfile
   }

  output {

      # Bam, index and md5 files
      File output_bam = SortBam.output_bam
      File output_bam_index = SortBam.output_bam_index
      File output_bam_md5 = SortBam.output_bam_md5


      #QC outputs
      File unsorted_base_distribution_by_cycle_pdf = CollectUnsortedReadgroupBamQualityMetrics.base_distribution_by_cycle_pdf
      File unsorted_base_distribution_by_cycle_metrics = CollectUnsortedReadgroupBamQualityMetrics.base_distribution_by_cycle_metrics
      File unsorted_insert_size_histogram_pdf = CollectUnsortedReadgroupBamQualityMetrics.insert_size_histogram_pdf
      File unsorted_insert_size_metrics = CollectUnsortedReadgroupBamQualityMetrics.insert_size_metrics
      File unsorted_quality_by_cycle_pdf = CollectUnsortedReadgroupBamQualityMetrics.quality_by_cycle_pdf
      File unsorted_quality_by_cycle_metrics = CollectUnsortedReadgroupBamQualityMetrics.quality_by_cycle_metrics
      File unsorted_quality_distribution_pdf = CollectUnsortedReadgroupBamQualityMetrics.quality_distribution_pdf
      File unsorted_quality_distribution_metrics = CollectUnsortedReadgroupBamQualityMetrics.quality_distribution_metrics
      File quality_yield_metrics = CollectQualityYieldMetrics.quality_yield_metrics
      # Misc processing files
      File duplicate_metrics = MarkDuplicates.duplicate_metrics

   }


#   output {
#    Array[File] bams = glob("output_dir/*.bam")
#      File output_bam = BwaMem.output_aligned_bam
#   }

  meta {
    allowNestedInputs: true
  }

}

