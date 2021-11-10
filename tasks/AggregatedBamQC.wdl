version 1.0

import "../tasks/QC.wdl" as QC
import "../structs/DNASeqStructs.wdl" as Structs

# WORKFLOW DEFINITION
workflow AggregatedBamQC {
input {
    File input_bam
    File input_bam_index
    String sample_name
    File haplotype_database_file
    DNASeqSingleSampleReferences references
    File? fingerprint_genotypes_file
    File? fingerprint_genotypes_index
    String? picard_module
  }

  # QC the final BAM (consolidated after scattered BQSR)
  call QC.CollectReadgroupBamQualityMetrics as CollectReadgroupBamQualityMetrics {
    input:
      input_bam = input_bam,
      input_bam_index = input_bam_index,
      output_bam_prefix = sample_name + ".readgroup",
      ref_dict = references.reference_fasta.ref_dict,
      ref_fasta = references.reference_fasta.ref_fasta,
      ref_fasta_index = references.reference_fasta.ref_fasta_index,
      picard_module = picard_module
  }

  # QC the final BAM some more (no such thing as too much QC)
  call QC.CollectAggregationMetrics as CollectAggregationMetrics {
    input:
      input_bam = input_bam,
      input_bam_index = input_bam_index,
      output_bam_prefix = sample_name,
      ref_dict = references.reference_fasta.ref_dict,
      ref_fasta = references.reference_fasta.ref_fasta,
      ref_fasta_index = references.reference_fasta.ref_fasta_index,
      picard_module = picard_module
  }

  if (defined(haplotype_database_file) && defined(fingerprint_genotypes_file)) {
    # Check the sample BAM fingerprint against the sample array
    call QC.CheckFingerprint as CheckFingerprint {
      input:
        input_bam = input_bam,
        input_bam_index = input_bam_index,
        haplotype_database_file = haplotype_database_file,
        genotypes = fingerprint_genotypes_file,
        genotypes_index = fingerprint_genotypes_index,
        output_basename = sample_name,
        sample = sample_name,
        picard_module = picard_module
    }
  }

  # Generate a checksum per readgroup in the final BAM
  call QC.CalculateReadGroupChecksum as CalculateReadGroupChecksum {
    input:
      input_bam = input_bam,
      input_bam_index = input_bam_index,
      read_group_md5_filename = sample_name + ".bam.read_group_md5",
      picard_module = picard_module
  }

  output {
    File read_group_alignment_summary_metrics = CollectReadgroupBamQualityMetrics.alignment_summary_metrics
    File read_group_gc_bias_detail_metrics = CollectReadgroupBamQualityMetrics.gc_bias_detail_metrics
    File read_group_gc_bias_pdf = CollectReadgroupBamQualityMetrics.gc_bias_pdf
    File read_group_gc_bias_summary_metrics = CollectReadgroupBamQualityMetrics.gc_bias_summary_metrics

    File calculate_read_group_checksum_md5 = CalculateReadGroupChecksum.md5_file

    File agg_alignment_summary_metrics = CollectAggregationMetrics.alignment_summary_metrics
    File agg_bait_bias_detail_metrics = CollectAggregationMetrics.bait_bias_detail_metrics
    File agg_bait_bias_summary_metrics = CollectAggregationMetrics.bait_bias_summary_metrics
    File agg_gc_bias_detail_metrics = CollectAggregationMetrics.gc_bias_detail_metrics
    File agg_gc_bias_pdf = CollectAggregationMetrics.gc_bias_pdf
    File agg_gc_bias_summary_metrics = CollectAggregationMetrics.gc_bias_summary_metrics
    File agg_insert_size_histogram_pdf = CollectAggregationMetrics.insert_size_histogram_pdf
    File agg_insert_size_metrics = CollectAggregationMetrics.insert_size_metrics
    File agg_pre_adapter_detail_metrics = CollectAggregationMetrics.pre_adapter_detail_metrics
    File agg_pre_adapter_summary_metrics = CollectAggregationMetrics.pre_adapter_summary_metrics
    File agg_quality_distribution_pdf = CollectAggregationMetrics.quality_distribution_pdf
    File agg_quality_distribution_metrics = CollectAggregationMetrics.quality_distribution_metrics
    File agg_error_summary_metrics = CollectAggregationMetrics.error_summary_metrics

    File? fingerprint_summary_metrics = CheckFingerprint.summary_metrics
    File? fingerprint_detail_metrics = CheckFingerprint.detail_metrics
  }
  meta {
    allowNestedInputs: true
  }
}
