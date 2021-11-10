# nsm-analysis


## Singularity image(s)

singularity  build /usr/local/images/nsm-tools.sif docker://bruggerk/nsm-tools


## Advanced usage

It is possible to use the workflows with binaries from different source
1. locally installed and available in the general $PATH
2. in a container image, need to adjust the config file to activate this. Normally one container image will contain all binaries
3. modules: set module(/version) for binaries in the input json files.