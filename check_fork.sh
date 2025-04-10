#!/bin/bash
# Pre-hook script to validate against workflow changes

# Source: https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables#default-environment-variables
# GITHUB_BASE_REF  => This is only set when the event that triggers a workflow run is either pull_request or pull_request_target
# GITHUB_HEAD_REF => The head ref or source branch of the pull request in a workflow run. This property is only set when the event that triggers a workflow run is either pull_request or pull_request_target
# GITHUB_REPOSITORY => The owner and repository name. For example, octocat/Hello-World.

check_if_fork(){
    if [ "$IS_FORK" == "null" ]; then
    # This isn't a PR, no need to validate.
        echo "Not a pull request, skipping validation"
        exit 0
    elif [ $IS_FORK == "false" ]; then
        echo "Internal PR. Skip validation"
        exit 0
    fi
    # This can be removed now
    if [ -z "$GITHUB_HEAD_REF" ]; then
        # This isn't a PR, no need to validate.
        echo "Not a pull request, skipping validation"
        exit 0
    fi
}


clone_repo_with_reference () {
    if [[ $# -ne 2 ]] ; then
        echo "Must supply both a branch and output directory"
        return 1
    fi
    BRANCH=$1
    OUTPUT_PATH=$2

    git clone clone_url --branch $BRANCH --single-branch --reference=$LOCAL_REPO_STORAGE_PATH/$GIT_REPO_FULL_NAME $OUTPUT_PATH/$GIT_REPO_FULL_NAME
    git clone $GITHUB_SERVER_URL/$GIT_REPO_FULL_NAME.git --branch $BRANCH --single-branch --reference=$LOCAL_REPO_STORAGE_PATH/$GIT_REPO_FULL_NAME $OUTPUT_PATH/$GIT_REPO_FULL_NAME
}


# Requires parameter of the branch to fetch; E.g: $MAIN_BRANCH_NAME
# Slower than clone with reference, but maybe we don't have the reference.
fetch_workflow() {
    if [[ $# -ne 2 ]] ; then
        echo "Must supply both a branch and output directory"
        return 1
    fi
    BRANCH=$1
    OUTPUT_PATH=$2
    cd $OUTPUT_PATH/$GIT_REPO_FULL_NAME
    git init
    git remote add -f origin $GITHUB_SERVER_URL/$GIT_REPO_FULL_NAME.git
    git config core.sparseCheckout true
    echo ".github" >> .git/info/sparse-checkout # Add to only pull the '.github' directory
    git pull origin $BRANCH
    cd -
}


prepare_workflow_directories() {
    mkdir -p "$MAIN_WORKFLOW_CLONE_PATH/$GIT_REPO_FULL_NAME"
    mkdir -p "$NEW_WORKFLOW_CLONE_PATH/$GIT_REPO_FULL_NAME"
    if [ -d "$LOCAL_REPO_STORAGE_PATH/$GIT_REPO_FULL_NAME" ]; then
        echo "[Info] Local copy exists, cloning with reference"
        clone_repo_with_reference "$MAIN_BRANCH_NAME" "$MAIN_WORKFLOW_CLONE_PATH"
        clone_repo_with_reference "$FORK_BRANCH_NAME" "$NEW_WORKFLOW_CLONE_PATH"
    else
        echo "[Info] Local copy doesnt exist, fetching"
        fetch_workflow "$MAIN_BRANCH_NAME" "$MAIN_WORKFLOW_CLONE_PATH"
        fetch_workflow "$FORK_BRANCH_NAME" "$NEW_WORKFLOW_CLONE_PATH"
    fi
}


compare_workflow_directories() {
    # Compare the two directories
    echo "[Info] Comparing the two directories"
    # Should we add `--quiet` to this?
    git diff --name-only --exit-code $MAIN_WORKFLOW_CLONE_PATH/$GIT_REPO_FULL_NAME/.github $NEW_WORKFLOW_CLONE_PATH/$GIT_REPO_FULL_NAME/.github
    if [[ $? -ne 0 ]]; then
        echo "[Error] Workflow files have changed, exiting with error code 1"
        exit 1
    fi
}


main() {
    LOCAL_REPO_STORAGE_PATH=/tmp/local_repos
    MAIN_WORKFLOW_CLONE_PATH=/tmp/main_workflow
    NEW_WORKFLOW_CLONE_PATH=/tmp/new_workflow

    MAIN_BRANCH_NAME=$(cat $GITHUB_EVENT_PATH | jq -r '.pull_request.base.ref')
    FORK_BRANCH_NAME=$(cat $GITHUB_EVENT_PATH | jq -r '.pull_request.head.ref')
    GIT_REPO_FULL_NAME=$(cat $GITHUB_EVENT_PATH | jq -r '.base.repo.full_name')
    GITHUB_SERVER_URL="https://github.com"
    IS_FORK=$(cat $GITHUB_EVENT_PATH | jq -r '.head.repo.fork')

    check_if_fork
    prepare_workflow_directories
    compare_workflow_directories
}
