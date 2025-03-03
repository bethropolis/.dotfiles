function proj
    set -l projects_dir ~/Projects

    # Check if Projects directory exists
    if not test -d $projects_dir
        echo "Error: Projects directory ($projects_dir) does not exist"
        return 1
    end

    # Case: No arguments - just cd to Projects directory
    if test (count $argv) -eq 0
        cd $projects_dir
        return
    end

    # Case: Too many arguments
    if test (count $argv) -gt 1
        echo "Error: Too many arguments. Usage: proj [project_name]"
        return 1
    end

    # Case: Single argument - try to cd to project subdirectory
    set -l project_path $projects_dir/$argv[1]

    if test -d $project_path
        cd $project_path
    else
        echo "Error: Project directory '$argv[1]' does not exist in $projects_dir"
        return 1
    end
end
