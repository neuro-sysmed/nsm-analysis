git reset --hard
git pull
rm nsm-analysis.zip
#vim workflows/dna_pipeline.wdl
zip nsm-analysis.zip workflows/*wdl tasks/*wdl utils/*wdl structs/*wdl vars/*wdl version.json
