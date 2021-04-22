version 1.0

import "../structs/DNASeqStructs.wdl" 

#import "../../tasks/Alignment.wdl" as Alignment
import "../tasks/QC.wdl" as QC
import "../tasks/BamUtils.wdl" as BamUtils
import "../tasks/Utils.wdl" as Utils
import "../tasks/VcfUtils.wdl" as VcfUtils




#import "../../vars/global.wdl" as global


workflow VariantCalling {

   input {
      DNASeqSingleSampleReferences references
      VariantCallingScatterSettings scatter_settings

#    File calling_interval_list
#    File evaluation_interval_list
    Float? contamination
    File input_bam
    File input_bam_index
#    ReferenceFasta references
#    File ref_fasta
#    File ref_fasta_index
#    File ref_dict
#    File dbsnp_vcf
#    File dbsnp_vcf_index
    String base_file_name
    String final_vcf_base_name
    Boolean make_gvcf = true
   }


  # Break the calling interval_list into sub-intervals
  # Perform variant calling on the sub-intervals, and then gather the results
  call Utils.ScatterIntervalList as ScatterIntervalList {
    input:
      interval_list = references.wgs_calling_interval_list,
      scatter_count = scatter_settings.haplotype_scatter_count,
      break_bands_at_multiples_of = scatter_settings.break_bands_at_multiples_of
  }

  # We need disk to localize the sharded input and output due to the scatter for HaplotypeCaller.
  # If we take the number we are scattering by and reduce by 20 we will have enough disk space
  # to account for the fact that the data is quite uneven across the shards.
  Int potential_hc_divisor = ScatterIntervalList.interval_count - 20
  Int hc_divisor = if potential_hc_divisor > 1 then potential_hc_divisor else 1

  # Call variants in parallel over WGS calling intervals
  scatter (scattered_interval_list in ScatterIntervalList.out) {

      # Generate GVCF by interval
      call BamUtils.HaplotypeCaller as HaplotypeCaller {
        input:
          contamination = contamination,
          input_bam = input_bam,
          input_bam_index = input_bam_index,
          interval_list = scattered_interval_list,
          vcf_basename = base_file_name,
          ref_dict = references.reference_fasta.ref_dict,
          ref_fasta = references.reference_fasta.ref_fasta,
          ref_fasta_index = references.reference_fasta.ref_fasta_index,
          hc_scatter = hc_divisor,
          make_gvcf = true,
       }

    File vcfs_to_merge = select_first([HaplotypeCaller.output_vcf])
    File vcf_indices_to_merge = select_first([HaplotypeCaller.output_vcf_index])
  }

  # Combine by-interval (g)VCFs into a single sample (g)VCF file
  String merge_suffix = if make_gvcf then ".g.vcf.gz" else ".vcf.gz"
  call VcfUtils.MergeVCFs as MergeVCFs {
    input:
      input_vcfs = vcfs_to_merge,
      input_vcfs_indexes = vcf_indices_to_merge,
      output_vcf_name = final_vcf_base_name + merge_suffix,
  }

  # Validate the (g)VCF output of HaplotypeCaller
  call QC.ValidateVCF as ValidateVCF {
    input:
      input_vcf = MergeVCFs.output_vcf,
      input_vcf_index = MergeVCFs.output_vcf_index,
      dbsnp_vcf = references.dbsnp_vcf,
      dbsnp_vcf_index = references.dbsnp_vcf_index,
      ref_fasta = references.reference_fasta.ref_fasta,
      ref_fasta_index = references.reference_fasta.ref_fasta_index,
      ref_dict = references.reference_fasta.ref_dict,
      calling_interval_list = references.wgs_calling_interval_list,
      is_gvcf = true,
  }

  # QC the (g)VCF
  call QC.CollectVariantCallingMetrics as CollectVariantCallingMetrics {
    input:
      input_vcf = MergeVCFs.output_vcf,
      input_vcf_index = MergeVCFs.output_vcf_index,
      metrics_basename = final_vcf_base_name,
      dbsnp_vcf = references.dbsnp_vcf,
      dbsnp_vcf_index = references.dbsnp_vcf_index,
      ref_dict = references.reference_fasta.ref_dict,
      evaluation_interval_list = references.evaluation_interval_list,
      is_gvcf = true,
  }

  output {
    File vcf_summary_metrics = CollectVariantCallingMetrics.summary_metrics
    File vcf_detail_metrics = CollectVariantCallingMetrics.detail_metrics
    File output_vcf = MergeVCFs.output_vcf
    File output_vcf_index = MergeVCFs.output_vcf_index
  }
      



#   output {
#    Array[File] bams = glob("output_dir/*.bam")
#      File output_bam = BwaMem.output_aligned_bam
#   }

  meta {
    allowNestedInputs: true
  }

}

