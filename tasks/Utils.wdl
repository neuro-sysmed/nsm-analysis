version 1.0


task Version {
    # shoudld be replaced with a wf and read_json, oh well

    command <<<
        RepoVersion=$(jq 'if .dev then 
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) +"-"+(.dev|tostring) 
            else 
            (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) end' \
            < /home/brugger/projects/nsm/nsm-analysis/version.json )


        echo "${RepoVersion}"

    >>>

    output {
        String repo_version = stdout()
    }
}