version 1.0

import "../structs/DNASeqStructs.wdl" 
import "../tasks/JointGenotypingTasks.wdl" as Tasks


workflow JointGenotyping {

  input {



    String callset_name
    File sample_name_map
    
    DNASeqSingleSampleReferences references



    Array[String] snp_recalibration_tranche_values
    Array[String] snp_recalibration_annotation_values
    Array[String] indel_recalibration_tranche_values
    Array[String] indel_recalibration_annotation_values

#    File hapmap_resource_vcf
#    File hapmap_resource_vcf_index
#    File omni_resource_vcf
#    File omni_resource_vcf_index
#    File one_thousand_genomes_resource_vcf
#    File one_thousand_genomes_resource_vcf_index
#    File mills_resource_vcf
#    File mills_resource_vcf_index
#    File axiomPoly_resource_vcf
#    File axiomPoly_resource_vcf_index

    # ExcessHet is a phred-scaled p-value. We want a cutoff of anything more extreme
    # than a z-score of -4.5 which is a p-value of 3.4e-06, which phred-scaled is 54.69
    Float excess_het_threshold = 54.69
    Float snp_filter_level
    Float indel_filter_level
    Int SNP_VQSR_downsampleFactor

    Int? top_level_scatter_count
    Boolean? gather_vcfs
    Int snps_variant_recalibration_threshold = 500000
    Float unbounded_scatter_count_scale_factor = 0.15
    Boolean use_allele_specific_annotations = true
  }

  Array[Array[String]] sample_name_map_lines = read_tsv(sample_name_map)
  Int num_gvcfs = length(sample_name_map_lines)

  # Make a 2.5:1 interval number to samples in callset ratio interval list.
  # We allow overriding the behavior by specifying the desired number of vcfs
  # to scatter over for testing / special requests.
  # Zamboni notes say "WGS runs get 30x more scattering than Exome" and
  # exome scatterCountPerSample is 0.05, min scatter 10, max 1000

  # For small callsets (fewer than 1000 samples) we can gather the VCF shards and collect metrics directly.
  # For anything larger, we need to keep the VCF sharded and gather metrics collected from them.
  # We allow overriding this default behavior for testing / special requests.
  Boolean is_small_callset = select_first([gather_vcfs, num_gvcfs <= 1000])

  Int unbounded_scatter_count = select_first([top_level_scatter_count, round(unbounded_scatter_count_scale_factor * num_gvcfs)])
  Int scatter_count = if unbounded_scatter_count > 2 then unbounded_scatter_count else 2 #I think weird things happen if scatterCount is 1 -- IntervalListTools is noop?

  call Tasks.CheckSamplesUnique  as CheckSamplesUnique {
    input:
      sample_name_map = sample_name_map
  }

  call Tasks.SplitIntervalList {
    input:
      interval_list = references.unpadded_intervals_file,
      scatter_count = scatter_count,
      ref_fasta = references.reference_fasta.ref_fasta,
      ref_fasta_index = references.reference_fasta.ref_fasta_index,
      ref_dict = references.reference_fasta.ref_dict,
      sample_names_unique_done = CheckSamplesUnique.samples_unique,
      gatk_module = gatk_module,
  }

  Array[File] unpadded_intervals = SplitIntervalList.output_intervals

  scatter (idx in range(length(unpadded_intervals))) {
    # The batch_size value was carefully chosen here as it
    # is the optimal value for the amount of memory allocated
    # within the task; please do not change it without consulting
    # the Hellbender (GATK engine) team!
    call Tasks.ImportGVCFs as ImportGVCFs {
      input:
        sample_name_map = sample_name_map,
        interval = unpadded_intervals[idx],
        workspace_dir_name = "genomicsdb",
        batch_size = 50,
        gatk_module = gatk_module,
    }


    call Tasks.GenotypeGVCFs as GenotypeGVCFs{
      input:
        workspace_tar = ImportGVCFs.output_genomicsdb,
        interval = unpadded_intervals[idx],
        output_vcf_filename = callset_name + "." + idx + ".vcf.gz",
        ref_fasta = references.reference_fasta.ref_fasta,
        ref_fasta_index = references.reference_fasta.ref_fasta_index,
        ref_dict = references.reference_fasta.ref_dict,
        dbsnp_vcf = references.dbsnp_vcf,
        dbsnp_vcf_index = references.dbsnp_vcf_index,
        gatk_module = gatk_module,
    }

    File genotyped_vcf =  GenotypeGVCFs.output_vcf
    File genotyped_vcf_index = GenotypeGVCFs.output_vcf_index

    call Tasks.HardFilterAndMakeSitesOnlyVcf {
      input:
        vcf = genotyped_vcf,
        vcf_index = genotyped_vcf_index,
        excess_het_threshold = excess_het_threshold,
        variant_filtered_vcf_filename = callset_name + "." + idx + ".variant_filtered.vcf.gz",
        sites_only_vcf_filename = callset_name + "." + idx + ".sites_only.variant_filtered.vcf.gz",
        gatk_module = gatk_module,
    }
  }

  call Tasks.GatherVcfs as SitesOnlyGatherVcf {
    input:
      input_vcfs = HardFilterAndMakeSitesOnlyVcf.sites_only_vcf,
      output_vcf_name = callset_name + ".sites_only.vcf.gz",
      gatk_module = gatk_module,
  }

  call Tasks.IndelsVariantRecalibrator {
    input:
      sites_only_variant_filtered_vcf = SitesOnlyGatherVcf.output_vcf,
      sites_only_variant_filtered_vcf_index = SitesOnlyGatherVcf.output_vcf_index,
      recalibration_filename = callset_name + ".indels.recal",
      tranches_filename = callset_name + ".indels.tranches",
      recalibration_tranche_values = indel_recalibration_tranche_values,
      recalibration_annotation_values = indel_recalibration_annotation_values,
      mills_resource_vcf = references.mills_resource_vcf,
      mills_resource_vcf_index = references.mills_resource_vcf_index,
      axiomPoly_resource_vcf = references.axiomPoly_resource_vcf,
      axiomPoly_resource_vcf_index = references.axiomPoly_resource_vcf_index,
      dbsnp_resource_vcf = references.dbsnp_vcf,
      dbsnp_resource_vcf_index = references.dbsnp_vcf_index,
      use_allele_specific_annotations = use_allele_specific_annotations,
      gatk_module = gatk_module,
  }

  if (num_gvcfs > snps_variant_recalibration_threshold) {
    call Tasks.SNPsVariantRecalibratorCreateModel {
      input:
        sites_only_variant_filtered_vcf = SitesOnlyGatherVcf.output_vcf,
        sites_only_variant_filtered_vcf_index = SitesOnlyGatherVcf.output_vcf_index,
        recalibration_filename = callset_name + ".snps.recal",
        tranches_filename = callset_name + ".snps.tranches",
        recalibration_tranche_values = snp_recalibration_tranche_values,
        recalibration_annotation_values = snp_recalibration_annotation_values,
        downsampleFactor = SNP_VQSR_downsampleFactor,
        model_report_filename = callset_name + ".snps.model.report",
        hapmap_resource_vcf = references.hapmap_resource_vcf,
        hapmap_resource_vcf_index = references.hapmap_resource_vcf_index,
        omni_resource_vcf = references.omni_resource_vcf,
        omni_resource_vcf_index = references.omni_resource_vcf_index,
        one_thousand_genomes_resource_vcf = references.one_thousand_genomes_resource_vcf,
        one_thousand_genomes_resource_vcf_index = references.one_thousand_genomes_resource_vcf_index,
        dbsnp_resource_vcf = references.dbsnp_vcf,
        dbsnp_resource_vcf_index = references.dbsnp_vcf_index,
        use_allele_specific_annotations = use_allele_specific_annotations,
        gatk_module = gatk_module,
    }

    scatter (idx in range(length(HardFilterAndMakeSitesOnlyVcf.sites_only_vcf))) {
      call Tasks.SNPsVariantRecalibrator as SNPsVariantRecalibratorScattered {
        input:
          sites_only_variant_filtered_vcf = HardFilterAndMakeSitesOnlyVcf.sites_only_vcf[idx],
          sites_only_variant_filtered_vcf_index = HardFilterAndMakeSitesOnlyVcf.sites_only_vcf_index[idx],
          recalibration_filename = callset_name + ".snps." + idx + ".recal",
          tranches_filename = callset_name + ".snps." + idx + ".tranches",
          recalibration_tranche_values = snp_recalibration_tranche_values,
          recalibration_annotation_values = snp_recalibration_annotation_values,
          model_report = SNPsVariantRecalibratorCreateModel.model_report,
          hapmap_resource_vcf = references.hapmap_resource_vcf,
          hapmap_resource_vcf_index = references.hapmap_resource_vcf_index,
          omni_resource_vcf = references.omni_resource_vcf,
          omni_resource_vcf_index = references.omni_resource_vcf_index,
          one_thousand_genomes_resource_vcf = references.one_thousand_genomes_resource_vcf,
          one_thousand_genomes_resource_vcf_index = references.one_thousand_genomes_resource_vcf_index,
          dbsnp_resource_vcf = references.dbsnp_vcf,
          dbsnp_resource_vcf_index = references.dbsnp_vcf_index,
          use_allele_specific_annotations = use_allele_specific_annotations,
          gatk_module = gatk_module,
        }
    }

    call Tasks.GatherTranches as SNPGatherTranches {
      input:
        tranches = SNPsVariantRecalibratorScattered.tranches,
        output_filename = callset_name + ".snps.gathered.tranches",
        mode = "SNP",
        gatk_module = gatk_module,
    }
  }

  if (num_gvcfs <= snps_variant_recalibration_threshold) {
    call Tasks.SNPsVariantRecalibrator as SNPsVariantRecalibratorClassic {
      input:
        sites_only_variant_filtered_vcf = SitesOnlyGatherVcf.output_vcf,
        sites_only_variant_filtered_vcf_index = SitesOnlyGatherVcf.output_vcf_index,
        recalibration_filename = callset_name + ".snps.recal",
        tranches_filename = callset_name + ".snps.tranches",
        recalibration_tranche_values = snp_recalibration_tranche_values,
        recalibration_annotation_values = snp_recalibration_annotation_values,
        hapmap_resource_vcf = references.hapmap_resource_vcf,
        hapmap_resource_vcf_index = references.hapmap_resource_vcf_index,
        omni_resource_vcf = references.omni_resource_vcf,
        omni_resource_vcf_index = references.omni_resource_vcf_index,
        one_thousand_genomes_resource_vcf = references.one_thousand_genomes_resource_vcf,
        one_thousand_genomes_resource_vcf_index = references.one_thousand_genomes_resource_vcf_index,
        dbsnp_resource_vcf = references.dbsnp_vcf,
        dbsnp_resource_vcf_index = references.dbsnp_vcf_index,
        use_allele_specific_annotations = use_allele_specific_annotations,
        gatk_module = gatk_module,
    }
  }

  scatter (idx in range(length(HardFilterAndMakeSitesOnlyVcf.variant_filtered_vcf))) {
    #for really large callsets we give to friends, just apply filters to the sites-only
    call Tasks.ApplyRecalibration {
      input:
        recalibrated_vcf_filename = callset_name + ".filtered." + idx + ".vcf.gz",
        input_vcf = HardFilterAndMakeSitesOnlyVcf.variant_filtered_vcf[idx],
        input_vcf_index = HardFilterAndMakeSitesOnlyVcf.variant_filtered_vcf_index[idx],
        indels_recalibration = IndelsVariantRecalibrator.recalibration,
        indels_recalibration_index = IndelsVariantRecalibrator.recalibration_index,
        indels_tranches = IndelsVariantRecalibrator.tranches,
        snps_recalibration = if defined(SNPsVariantRecalibratorScattered.recalibration) then select_first([SNPsVariantRecalibratorScattered.recalibration])[idx] else select_first([SNPsVariantRecalibratorClassic.recalibration]),
        snps_recalibration_index = if defined(SNPsVariantRecalibratorScattered.recalibration_index) then select_first([SNPsVariantRecalibratorScattered.recalibration_index])[idx] else select_first([SNPsVariantRecalibratorClassic.recalibration_index]),
        snps_tranches = select_first([SNPGatherTranches.tranches_file, SNPsVariantRecalibratorClassic.tranches]),
        indel_filter_level = indel_filter_level,
        snp_filter_level = snp_filter_level,
        use_allele_specific_annotations = use_allele_specific_annotations,
        gatk_module = gatk_module,
    }

    # For large callsets we need to collect metrics from the shards and gather them later.
    if (!is_small_callset) {
      call Tasks.CollectVariantCallingMetrics as CollectMetricsSharded {
        input:
          input_vcf = ApplyRecalibration.recalibrated_vcf,
          input_vcf_index = ApplyRecalibration.recalibrated_vcf_index,
          metrics_filename_prefix = callset_name + "." + idx,
          dbsnp_vcf = references.dbsnp_vcf,
          dbsnp_vcf_index = references.dbsnp_vcf_index,
          interval_list = references.evaluation_interval_list,
          ref_dict = references.reference_fasta.ref_dict,
          gatk_module = gatk_module,
      }
    }
  }

  # For small callsets we can gather the VCF shards and then collect metrics on it.
  if (is_small_callset) {
    call Tasks.GatherVcfs as FinalGatherVcf {
      input:
        input_vcfs = ApplyRecalibration.recalibrated_vcf,
        output_vcf_name = callset_name + ".vcf.gz",
        gatk_module = gatk_module,
    }

    call Tasks.CollectVariantCallingMetrics as CollectMetricsOnFullVcf {
      input:
        input_vcf = FinalGatherVcf.output_vcf,
        input_vcf_index = FinalGatherVcf.output_vcf_index,
        metrics_filename_prefix = callset_name,
        dbsnp_vcf = references.dbsnp_vcf,
        dbsnp_vcf_index = references.dbsnp_vcf_index,
        interval_list = references.evaluation_interval_list,
        ref_dict = references.reference_fasta.ref_dict,
        gatk_module = gatk_module,
    }
  }

  if (!is_small_callset) {
    # For large callsets we still need to gather the sharded metrics.
    call Tasks.GatherVariantCallingMetrics {
      input:
        input_details = select_all(CollectMetricsSharded.detail_metrics_file),
        input_summaries = select_all(CollectMetricsSharded.summary_metrics_file),
        output_prefix = callset_name,
        gatk_module = gatk_module,
    }
  }
  # Get the metrics from either code path
  File output_detail_metrics_file = select_first([CollectMetricsOnFullVcf.detail_metrics_file, GatherVariantCallingMetrics.detail_metrics_file])
  File output_summary_metrics_file = select_first([CollectMetricsOnFullVcf.summary_metrics_file, GatherVariantCallingMetrics.summary_metrics_file])

  # Get the VCFs from either code path
  Array[File?] output_vcf_files = if defined(FinalGatherVcf.output_vcf) then [FinalGatherVcf.output_vcf] else ApplyRecalibration.recalibrated_vcf
  Array[File?] output_vcf_index_files = if defined(FinalGatherVcf.output_vcf_index) then [FinalGatherVcf.output_vcf_index] else ApplyRecalibration.recalibrated_vcf_index

  output {
    # Metrics from either the small or large callset
    File detail_metrics_file = output_detail_metrics_file
    File summary_metrics_file = output_summary_metrics_file

    # Outputs from the small callset path through the wdl.
    Array[File] output_vcfs = select_all(output_vcf_files)
    Array[File] output_vcf_indices = select_all(output_vcf_index_files)

    # Output the interval list generated/used by this run workflow.
    Array[File] output_intervals = SplitIntervalList.output_intervals

    # Output the metrics from crosschecking fingerprints.
  }
  meta {
    allowNestedInputs: true
  }
}
