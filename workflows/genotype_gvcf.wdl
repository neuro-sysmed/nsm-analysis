version 1.0

import "../structs/DNASeqStructs.wdl" 

import "../tasks/QC.wdl" as QC
import "../tasks/VcfUtils.wdl" as VcfUtils


workflow GenotypeGvcf {

   input {
      String sample_name
      File gvcf_file
      File gvcf_file_index
      DNASeqSingleSampleReferences references

      String? picard_module
      String? gatk_module

   }


  # Validate the gVCF 
  call QC.ValidateVCF as ValidateVCF {
    input:
      input_vcf = gvcf_file,
      input_vcf_index = gvcf_file_index,
      dbsnp_vcf = references.dbsnp_vcf,
      dbsnp_vcf_index = references.dbsnp_vcf_index,
      ref_fasta = references.reference_fasta.ref_fasta,
      ref_fasta_index = references.reference_fasta.ref_fasta_index,
      ref_dict = references.reference_fasta.ref_dict,
      calling_interval_list = references.wgs_calling_interval_list,
      is_gvcf = true,
      gatk_module = gatk_module,
  }

  call VcfUtils.GenotypeGVCF as GenotypeGVCF {
    input:
      input_gvcf = gvcf_file,
      input_gvcf_index = gvcf_file_index,
      output_vcf_name = sample_name + ".vcf.gz",
      reference_fasta = references.reference_fasta.ref_fasta,
      reference_fasta_index = references.reference_fasta.ref_fasta_index,
      reference_dict = references.reference_fasta.ref_dict,
      gatk_module = gatk_module,
  }

  # QC the VCF
  call QC.CollectVariantCallingMetrics as CollectVariantCallingMetrics {
    input:
      input_vcf = GenotypeGVCF.output_vcf,
      input_vcf_index = GenotypeGVCF.output_vcf_index,
      metrics_basename = sample_name+".vcf",
      dbsnp_vcf = references.dbsnp_vcf,
      dbsnp_vcf_index = references.dbsnp_vcf_index,
      ref_dict = references.reference_fasta.ref_dict,
      evaluation_interval_list = references.evaluation_interval_list,
      is_gvcf = true,
      picard_module = picard_module,
  }


  output {
    File vcf_summary_metrics  = CollectVariantCallingMetrics.summary_metrics
    File vcf_detail_metrics   = CollectVariantCallingMetrics.detail_metrics
    File output_vcf           = GenotypeGVCF.output_vcf
    File output_vcf_index     = GenotypeGVCF.output_vcf_index
  }
  
  meta {
    allowNestedInputs: true
  }

}

