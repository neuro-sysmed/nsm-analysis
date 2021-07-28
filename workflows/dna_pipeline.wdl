version 1.0


# Relative to wf file!

import "../tasks/Utils.wdl" as Utils
import "../tasks/Alignment.wdl" as Alignment
import "../tasks/QC.wdl" as QC
import "../tasks/BamUtils.wdl" as BamUtils
import "../tasks/Versions.wdl" as Versions


import "../tasks/AggregatedBamQC.wdl" as AggregatedBamQC

import "../workflows/haplotype_caller.wdl" as HaplotypeCaller


import "../structs/DNASeqStructs.wdl" as Structs


workflow DNAProcessing {

   input {
      SampleAndUnmappedBams sample_and_unmapped_bams
      DNASeqSingleSampleReferences references
      Boolean WGS = false
      Boolean doBSQR = false
      Boolean somatic = false
      Boolean bin_base_qualities = true
      Int compression_level = 5
      Boolean hard_clip_reads = false
      VariantCallingScatterSettings scatter_settings

   }

   # Easier to refer to it later on.
   String sample_name  = sample_and_unmapped_bams.sample_name
   
   call Versions.Versions as Versions

   call Utils.Sleep {
      input:
        linker = Versions.Star
   }

   scatter (unmapped_bam in sample_and_unmapped_bams.unmapped_bams) {

      String bam_basename = basename(unmapped_bam)


      call QC.CollectQualityYieldMetrics as CollectQualityYieldMetrics {
         input:
         input_bam = unmapped_bam,
         metrics_filename = bam_basename + ".quality_yield_metrics",
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
            output_bam_prefix = BwaMem.aligned_bam + ".qc.readgroup_bam_quality_metrics",
      }
     
   }

   call BamUtils.MergeAndMarkDuplicates as MarkDuplicates {
      input:
         input_bams = BwaMem.aligned_bam,
         output_bam_basename = sample_name + ".bam",
         metrics_filename = sample_name + ".bam.duplicate_metrics",
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
         bamfile = BamAddImageVersion.output_bam,
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
         output_bam_basename = sample_name + ".aligned.duplicate_marked.sorted",
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
               output_bam_basename = sample_name + ".aligned.duplicate_marked.sorted.bqsr",
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
   File aligned_bam_md5 = select_first([GatherBamFiles.output_bam_md5, SortBam.output_bam_md5 ])

   call AggregatedBamQC.AggregatedBamQC {
    input:
      input_bam = aligned_bam,
      input_bam_index = aligned_bam_index,
      sample_name = sample_name,
      haplotype_database_file = references.haplotype_database_file,
      references = references
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

   call HaplotypeCaller.VariantCalling as HaplotypeCaller {
      input:
         references = references,
         scatter_settings = scatter_settings,
         input_bam = BamAddPipelineVersion.output_bam,
         input_bam_index = BamAddPipelineVersion.output_bam + '.bai',
         base_file_name = sample_name,
         final_vcf_base_name = sample_name + ".vcf"
   }



  output {

      # Bam, index and md5 files
      File output_bam       = aligned_bam
      File output_bam_index = aligned_bam_index
      File output_bam_md5   = aligned_bam_md5

      File metrics_duplicates = MarkDuplicates.duplicate_metrics


      #QC outputs
      Array[File] qc_quality_yield_metrics = CollectQualityYieldMetrics.quality_yield_metrics

      Array[File] qc_unsorted_base_distribution_by_cycle_pdf     = CollectUnsortedReadgroupBamQualityMetrics.base_distribution_by_cycle_pdf
      Array[File] qc_unsorted_base_distribution_by_cycle_metrics = CollectUnsortedReadgroupBamQualityMetrics.base_distribution_by_cycle_metrics
      Array[File] qc_unsorted_insert_size_histogram_pdf          = CollectUnsortedReadgroupBamQualityMetrics.insert_size_histogram_pdf
      Array[File] qc_unsorted_insert_size_metrics                = CollectUnsortedReadgroupBamQualityMetrics.insert_size_metrics
      Array[File] qc_unsorted_quality_by_cycle_pdf               = CollectUnsortedReadgroupBamQualityMetrics.quality_by_cycle_pdf
      Array[File] qc_unsorted_quality_by_cycle_metrics           = CollectUnsortedReadgroupBamQualityMetrics.quality_by_cycle_metrics
      Array[File] qc_unsorted_quality_distribution_pdf           = CollectUnsortedReadgroupBamQualityMetrics.quality_distribution_pdf
      Array[File] qc_unsorted_quality_distribution_metrics       = CollectUnsortedReadgroupBamQualityMetrics.quality_distribution_metrics

      File qc_quality_distribution_metrics         = AggregatedBamQC.agg_quality_distribution_metrics
      File qc_alignment_summary_metrics            = AggregatedBamQC.agg_alignment_summary_metrics
      File qc_error_summary_metrics                = AggregatedBamQC.agg_error_summary_metrics
      File qc_read_group_gc_bias_summary_metrics   = AggregatedBamQC.read_group_gc_bias_summary_metrics
      File qc_calculate_read_group_checksum_md5    = AggregatedBamQC.calculate_read_group_checksum_md5
      File qc_gc_bias_detail_metrics               = AggregatedBamQC.agg_gc_bias_detail_metrics
      File qc_read_group_alignment_summary_metrics = AggregatedBamQC.read_group_alignment_summary_metrics
      File? qc_fingerprint_summary_metrics         = AggregatedBamQC.fingerprint_summary_metrics
      File? qc_fingerprint_detail_metrics          = AggregatedBamQC.fingerprint_detail_metrics
      File qc_gc_bias_summary_metrics              = AggregatedBamQC.agg_gc_bias_summary_metrics
      File qc_quality_distribution_pdf             = AggregatedBamQC.agg_quality_distribution_pdf
      File qc_bait_bias_summary_metrics            = AggregatedBamQC.agg_bait_bias_summary_metrics
      File qc_bait_bias_detail_metrics             = AggregatedBamQC.agg_bait_bias_detail_metrics
      File qc_gc_bias_pdf                          = AggregatedBamQC.agg_gc_bias_pdf
      File qc_pre_adapter_summary_metrics          = AggregatedBamQC.agg_pre_adapter_summary_metrics
      File qc_read_group_gc_bias_detail_metrics    = AggregatedBamQC.read_group_gc_bias_detail_metrics
      File qc_pre_adapter_detail_metrics           = AggregatedBamQC.agg_pre_adapter_detail_metrics
      File qc_insert_size_metrics                  = AggregatedBamQC.agg_insert_size_metrics
      File qc_group_gc_bias_pdf                    = AggregatedBamQC.read_group_gc_bias_pdf
      File qc_insert_size_histogram_pdf            = AggregatedBamQC.agg_insert_size_histogram_pdf

      File? qc_wgs_metrics = CollectWgsMetrics.metrics
      File? qc_raw_wgs_metrics = CollectRawWgsMetrics.metrics
      File? qc_Hs_metrics = CollectHsMetrics.metrics

   }



#   output {
#    Array[File] bams = glob("output_dir/*.bam")
#      File output_bam = BwaMem.output_aligned_bam
#   }

  meta {
    allowNestedInputs: true
  }

}

