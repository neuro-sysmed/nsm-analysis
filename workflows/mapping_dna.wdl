version 1.0


# Relative to wf file!

import "../tasks/Alignment.wdl" as Alignment
import "../tasks/QC.wdl" as QC
import "../tasks/BamUtils.wdl" as BamUtils
import "../tasks/Utils.wdl" as Utils
import "../tasks/Versions.wdl" as Versions

import "../tasks/AggregatedBamQC.wdl" as AggregatedBamQC


import "../structs/DNASeqStructs.wdl" as Structs
import "../vars/global.wdl" as global


workflow DNAPreprocessing {

   input {
      SampleAndUnmappedBams sample_and_unmapped_bams
      DNASeqSingleSampleReferences references
      Boolean WGS = false
      Boolean doBSQR = false
      Boolean somatic = false
      Boolean bin_base_qualities = true
      Int compression_level = 3
   }





   String sample_basename  = sample_and_unmapped_bams.base_filename
   Boolean hard_clip_reads = false

   call global.global
   call Versions.Versions as Versions


   scatter (unmapped_bam in sample_and_unmapped_bams.unmapped_bams) {

      String bam_basename = basename(unmapped_bam, sample_and_unmapped_bams.unmapped_bam_suffix)


      call QC.CollectQualityYieldMetrics as CollectQualityYieldMetrics {
         input:
         input_bam = unmapped_bam,
         metrics_filename = bam_basename + ".ubam.qc.quality_yield_metrics",
      }


      call Alignment.BwaMem as BwaMem {
         input:
            input_bam = unmapped_bam,
            bam_basename = bam_basename + ".aligned.unsorted",
            reference_fasta = references.reference_fasta,
            compression_level = compression_level,
            hard_clip_reads = hard_clip_reads,      
      }

      call QC.CollectUnsortedReadgroupBamQualityMetrics as CollectUnsortedReadgroupBamQualityMetrics {
         input:
            input_bam = BwaMem.aligned_bam,
            output_bam_prefix = BwaMem.aligned_bam + "qc.readgroup_bam_quality_metrics",
      }
     
   }

   call BamUtils.MergeAndMarkDuplicates as MarkDuplicates {
      input:
         input_bams = BwaMem.aligned_bam,
         output_bam_basename = sample_basename + ".aligned.unsorted.duplicates_marked",
         metrics_filename = sample_basename + ".aligned.unsorted.duplicates_marked.bam.duplicate_metrics",
#      total_input_size = SumFloats.total_size,
         compression_level = compression_level,
   }

    call BamUtils.BamAddProgramLine as BamAddImageVersion {
        input:
            bamfile = MarkDuplicates.output_bam,
            id = 'nsm-tools-image',
            version = Versions.image
    }


   call BamUtils.BamAddProgramLine as BamAddPipelineVersion {
      input:
         bamfile = BamAddImagesamtooVersion.output_bam,
         id = 'nsm-analysis',
         version = Versions.package

    }


#   call Utils.TotalReads as TotalReads {
#      input:
#         QualityYieldMetricsFiles = CollectQualityYieldMetrics.quality_yield_metrics      
#   }


  # Sort aggregated+deduped BAM file and fix tags
   call BamUtils.SortSam as SortBam {
      input:
         input_bam = BamAddPipelineVersion.output_bam,
         output_bam_basename = sample_basename + ".aligned.duplicate_marked.sorted",
         compression_level = compression_level,
   }

  Int bqsr_divisor = 1


   #User have to specify that bsqr should be done, mainly for genomes!
   if (doBSQR) {
      # Create list of sequences for scatter-gather parallelization
      call Utils.CreateSequenceGroupingTSV as CreateSequenceGroupingTSV {
         input:
            ref_dict = references.reference_fasta.ref_dict,
      }

        # Perform Base Quality Score Recalibration (BQSR) on the sorted BAM in parallel
      scatter (subgroup in CreateSequenceGroupingTSV.sequence_grouping) {
         # Generate the recalibration model by interval
         call BamUtils.BaseRecalibrator as BaseRecalibrator {
            input:
               input_bam = SortBam.output_bam,
               input_bam_index = SortBam.output_bam_index,
               recalibration_report_filename = sample_and_unmapped_bams.base_filename + ".recal_data.csv",
               sequence_group_interval = subgroup,
               dbsnp_vcf = references.dbsnp_vcf,
               dbsnp_vcf_index = references.dbsnp_vcf_index,
               known_indels_sites_vcfs = references.known_indels_sites_vcfs,
               known_indels_sites_indices = references.known_indels_sites_indices,
               ref_dict = references.reference_fasta.ref_dict,
               ref_fasta = references.reference_fasta.ref_fasta,
               ref_fasta_index = references.reference_fasta.ref_fasta_index,
               bqsr_scatter = bqsr_divisor
         }
      }

      # Merge the recalibration reports resulting from by-interval recalibration
      # The reports are always the same size
      call BamUtils.GatherBqsrReports as GatherBqsrReports {
         input:
            input_bqsr_reports = BaseRecalibrator.recalibration_report,
            output_report_filename = sample_and_unmapped_bams.base_filename + ".recal_data.csv",
      }

      scatter (subgroup in CreateSequenceGroupingTSV.sequence_grouping_with_unmapped) {
         # Apply the recalibration model by interval
         call BamUtils.ApplyBQSR as ApplyBQSR {
            input:
               input_bam = SortBam.output_bam,
               input_bam_index = SortBam.output_bam_index,
               output_bam_basename = sample_basename + ".aligned.duplicate_marked.sorted.bqsr",
               recalibration_report = GatherBqsrReports.output_bqsr_report,
               sequence_group_interval = subgroup,
               ref_dict = references.reference_fasta.ref_dict,
               ref_fasta = references.reference_fasta.ref_fasta,
               ref_fasta_index = references.reference_fasta.ref_fasta_index,
               bqsr_scatter = bqsr_divisor,
               compression_level = compression_level,
               bin_base_qualities = bin_base_qualities,
               somatic = somatic
         }
      }

      Float agg_bam_size = size(SortBam.output_bam, "GiB")

      # Merge the recalibrated BAM files resulting from by-interval recalibration
      call BamUtils.GatherSortedBamFiles as GatherBamFiles {
         input:
            input_bams = ApplyBQSR.recalibrated_bam,
            output_bam_basename = sample_and_unmapped_bams.base_filename,
            total_input_size = agg_bam_size,
            compression_level = compression_level
      }

   }

   # picks first non null value, so if recalibration is done this will be the first one
   File aligned_bam       = select_first([GatherBamFiles.output_bam, SortBam.output_bam])
   File aligned_bam_index = select_first([GatherBamFiles.output_bam_index, SortBam.output_bam_index ])

   call AggregatedBamQC.AggregatedBamQC {
    input:
      base_recalibrated_bam = aligned_bam,
      base_recalibrated_bam_index = aligned_bam_index,
      base_name = sample_and_unmapped_bams.base_filename,
      sample_name = sample_and_unmapped_bams.sample_name,
      recalibrated_bam_base_name = sample_and_unmapped_bams.base_filename,
      haplotype_database_file = references.haplotype_database_file,
      references = references,
  }


   if (WGS) {
      call QC.CollectWgsMetrics as CollectWgsMetrics {
         input:
            input_bam = aligned_bam,
            input_bam_index = aligned_bam_index,
            metrics_filename = sample_and_unmapped_bams.base_filename + ".wgs_metrics",
            ref_fasta = references.reference_fasta.ref_fasta,
            ref_fasta_index = references.reference_fasta.ref_fasta_index,
            wgs_coverage_interval_list = references.wgs_calling_interval_list,
            read_length = 250,
      }

      # QC the sample raw WGS metrics (common thresholds)
      call QC.CollectRawWgsMetrics as CollectRawWgsMetrics {
         input:
            input_bam = aligned_bam,
            input_bam_index = aligned_bam_index,
            metrics_filename = sample_and_unmapped_bams.base_filename + ".raw_wgs_metrics",
            ref_fasta = references.reference_fasta.ref_fasta,
            ref_fasta_index = references.reference_fasta.ref_fasta_index,
            wgs_coverage_interval_list = references.wgs_calling_interval_list,
            read_length = 250 ,
      }      
   }
   if (!WGS) {
      call QC.CollectHsMetrics as CollectHsMetrics {
         input:
            input_bam = aligned_bam,
            input_bam_index = aligned_bam_index,
            metrics_filename = sample_and_unmapped_bams.base_filename + ".hybrid_selection_metrics",
            ref_fasta = references.reference_fasta.ref_fasta,
            ref_fasta_index = references.reference_fasta.ref_fasta_index,
            target_interval_list = references.exome_calling_interval_list,
            bait_interval_list = references.exome_calling_interval_list
  }

   }


  output {

      # Bam, index and md5 files
      File output_bam = SortBam.output_bam
      File output_bam_index = SortBam.output_bam_index
      File output_bam_md5 = SortBam.output_bam_md5


      #QC outputs
#      Array[File] unsorted_read_group_base_distribution_by_cycle_pdf = UnmappedBamToAlignedBam.unsorted_read_group_base_distribution_by_cycle_pdf
#      Array[File] unsorted_read_group_base_distribution_by_cycle_metrics = UnmappedBamToAlignedBam.unsorted_read_group_base_distribution_by_cycle_metrics
#      Array[File] unsorted_read_group_insert_size_histogram_pdf = UnmappedBamToAlignedBam.unsorted_read_group_insert_size_histogram_pdf
#      Array[File] unsorted_read_group_insert_size_metrics = UnmappedBamToAlignedBam.unsorted_read_group_insert_size_metrics
#      Array[File] unsorted_read_group_quality_by_cycle_pdf = UnmappedBamToAlignedBam.unsorted_read_group_quality_by_cycle_pdf
#      Array[File] unsorted_read_group_quality_by_cycle_metrics = UnmappedBamToAlignedBam.unsorted_read_group_quality_by_cycle_metrics
#      Array[File] unsorted_read_group_quality_distribution_pdf = UnmappedBamToAlignedBam.unsorted_read_group_quality_distribution_pdf
#      Array[File] unsorted_read_group_quality_distribution_metrics = UnmappedBamToAlignedBam.unsorted_read_group_quality_distribution_metrics

#      File unsorted_base_distribution_by_cycle_pdf = CollectUnsortedReadgroupBamQualityMetrics.base_distribution_by_cycle_pdf
#      File unsorted_base_distribution_by_cycle_metrics = CollectUnsortedReadgroupBamQualityMetrics.base_distribution_by_cycle_metrics
#      File unsorted_insert_size_histogram_pdf = CollectUnsortedReadgroupBamQualityMetrics.insert_size_histogram_pdf
#      File unsorted_insert_size_metrics = CollectUnsortedReadgroupBamQualityMetrics.insert_size_metrics
#      File unsorted_quality_by_cycle_pdf = CollectUnsortedReadgroupBamQualityMetrics.quality_by_cycle_pdf
#      File unsorted_quality_by_cycle_metrics = CollectUnsortedReadgroupBamQualityMetrics.quality_by_cycle_metrics
#      File unsorted_quality_distribution_pdf = CollectUnsortedReadgroupBamQualityMetrics.quality_distribution_pdf
#      File unsorted_quality_distribution_metrics = CollectUnsortedReadgroupBamQualityMetrics.quality_distribution_metrics
#      File quality_yield_metrics = CollectQualityYieldMetrics.quality_yield_metrics
      # Misc processing files
      File duplicate_metrics = MarkDuplicates.duplicate_metrics
      File? rawwgs_metrics = CollectRawWgsMetrics.metrics


   }


#   output {
#    Array[File] bams = glob("output_dir/*.bam")
#      File output_bam = BwaMem.output_aligned_bam
#   }

  meta {
    allowNestedInputs: true
  }

}

