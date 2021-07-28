version 1.0

import "../structs/DNASeqStructs.wdl" 

#import "../../tasks/Alignment.wdl" as Alignment
import "../tasks/QC.wdl" as QC
import "../tasks/BamUtils.wdl" as BamUtils
import "../tasks/Utils.wdl" as Utils
import "../tasks/VcfUtils.wdl" as VcfUtils


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
  String merge_suffix = if make_gvcf then ".gvcf.gz" else ".vcf.gz"
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

  call VcfUtils.GenotypeGVCF as GenotypeGVCF {
    input:
      input_gvcf = MergeVCFs.output_vcf,
      input_gvcf_index = MergeVCFs.output_vcf_index,
      output_vcf_name = final_vcf_base_name + ".vcf.gz",
      reference_fasta = references.reference_fasta.ref_fasta,
      reference_fasta_index = references.reference_fasta.ref_fasta_index,
      reference_dict = references.reference_fasta.ref_dict,
  }

  # QC the gVCF
  call QC.CollectVariantCallingMetrics as CollectVariantCallingMetrics {
    input:
      input_vcf = MergeVCFs.output_vcf,
      input_vcf_index = MergeVCFs.output_vcf_index,
      metrics_basename = final_vcf_base_name+".gvcf",
      dbsnp_vcf = references.dbsnp_vcf,
      dbsnp_vcf_index = references.dbsnp_vcf_index,
      ref_dict = references.reference_fasta.ref_dict,
      evaluation_interval_list = references.evaluation_interval_list,
      is_gvcf = true,
  }

  # QC the VCF
  call QC.CollectVariantCallingMetrics as CollectVariantCallingMetrics {
    input:
      input_vcf = GenotypeGVCF.output_vcf,
      input_vcf_index = GenotypeGVCF.output_vcf_index,
      metrics_basename = final_vcf_base_name+".vcf",
      dbsnp_vcf = references.dbsnp_vcf,
      dbsnp_vcf_index = references.dbsnp_vcf_index,
      ref_dict = references.reference_fasta.ref_dict,
      evaluation_interval_list = references.evaluation_interval_list,
      is_gvcf = true,
  }


# gatk GenotypeGVCFs -V NA12878.g.vcf.gz -R Homo_sapiens_assembly38.fasta -O NA12878.vcf  -G StandardAnnotation -G AS_StandardAnnotation 
# gatk VariantRecalibrator -O NA12878.snp.recall -V NA12878.vcf --resource:hapmap,known=false,training=true,truth=true,prior=15.0 ../../hg38/hapmap_3.3.hg38.vcf.gz --resource:omni,known=false,training=true,truth=false,prior=12.0 ../../hg38/1000G_omni2.5.hg38.vcf.gz --resource:1000G,known=false,training=true,truth=false,prior=10.0 ../../hg38/1000G_phase1.snps.high_confidence.hg38.vcf.gz --resource:dbsnp,known=true,training=false,truth=false,prior=2.0 ../../hg38/Homo_sapiens_assembly38.dbsnp138.vcf  --tranches-file output.tranches --use-allele-specific-annotations  --trust-all-polymorphic --max-gaussians 6  -an AS_MQRankSum -an AS_ReadPosRankSum -an AS_FS -an AS_MQ -an AS_SOR -tranche 100.0 -tranche 99.95 -tranche 99.9 -tranche 99.5 -tranche 99.0 -tranche 97.0 -tranche 96.0 -tranche 95.0 -tranche 94.0 -tranche 93.5 -tranche 93.0 -tranche 92.0 -tranche 91.0 -tranche 90.0 




  output {
    File vcf_summary_metrics = CollectVariantCallingMetrics.summary_metrics
    File vcf_detail_metrics = CollectVariantCallingMetrics.detail_metrics
    File output_gvcf = MergeVCFs.output_vcf
    File output_gvcf_index = MergeVCFs.output_vcf_index
    File output_vcf = GenotypeGVCF.output_vcf
    File output_vcf_index = GenotypeGVCF.output_vcf_index
  }
      



#   output {
#    Array[File] bams = glob("output_dir/*.bam")
#      File output_bam = BwaMem.output_aligned_bam
#   }

  meta {
    allowNestedInputs: true
  }

}

