version 1.0



workflow Singularity  {

  call SingularityTask {
    input:
      container = "/home/brugger/projects/kbr-tools/nsm-tools.sif",
      cmd       = "echo 'Hello world non-default'"      
  }

#    String container_s = "/home/brugger/projects/kbr-tools/nsm-tools.sif"

   output {
     String message = SingularityTask.message
   }

  meta {
    allowNestedInputs: true
  }

}

task SingularityTask {
  input {
    String container = "bruggerk/nsm-toolss"
    String? cmd = 'echo "Hello world"'
  }


  command {
    ~{cmd}

  }
  runtime {
# uncomment both to run with a singularity image    
#    backend: 'singularity'
    image: container
  }



  output {
    String message = stdout()
  }

}