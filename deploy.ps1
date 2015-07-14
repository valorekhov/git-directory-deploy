
# port of git-directory-deploy.sh to Powershell
# https://github.com/X1011/git-directory-deploy

# BSD 3-Clause License:

# Copyright Val Orekhov
# Original Script Copyright Daniel Smith
# All rights reserved.

# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:

#   Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.

#   Redistributions in binary form must reproduce the above copyright notice, this
#   list of conditions and the following disclaimer in the documentation and/or
#   other materials provided with the distribution.

#   The names of the contributors may not be used to endorse or promote products
#   derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

param(
    [string]$deploy_directory = "dist",  #set directory and branch
    [string]$deploy_branch = "deployment", 
    [string]$default_username,  #if no user identity is already set in the current git environment, use this
    [string]$default_email,
    [switch]$allow_empty,
    [Parameter(Mandatory=$true)]
    [string]$repo               #repository to deploy to. must be readable and writable.
)


$ErrorActionPreference = "Stop" #abort if any command fails
$git = 'git.exe'

$verbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent -or $false

#echo expanded commands as they are executed (for debugging)
function enable_expanded_output() {
    if ($verbose) {
        Set-PSDebug -Trace 1
    }
}

#this is used to avoid outputting the repo URL, which may contain a secret token
function disable_expanded_output() {
    Set-PSDebug -Trace 0
}

#enable_expanded_output

function set_user_id() {
    $name = (&$git config user.name)
    if (-not $name) {
        write-host "Setting $name"
        &$git config user.name $default_username
    }
    $email = (&$git config user.email)
    if (-not $email) {
        write-host "Setting $email"
        &$git config user.email "$default_email"
    }
}

function restore_head() {
    if ($previous_branch -eq "HEAD" ) {
        #we weren't on any branch before, so just set HEAD back to the commit it was on
        &$git update-ref --no-deref HEAD $commit_hash $deploy_branch
    }
    else {
        write-host "Reverting to branch '$previous_branch'"
        &$git symbolic-ref HEAD "refs/heads/$previous_branch"
    }
    
    &$git reset --mixed
}

&$git diff --exit-code --quiet --cached

if ($LastExitCode -ne 0) {
    Write-Error "Aborting due to uncommitted changes in the index" 
    exit 1
}


$commit_title=(&$git log -n 1 --format="%s" HEAD)
$commit_hash=(&$git log -n 1 --format="%H" HEAD)
$previous_branch=(&$git rev-parse --abbrev-ref HEAD)

write-host "Current state:`n COMMIT: $commit_title / $commit_hash`n On $previous_branch"

if ( -not (Test-Path $deploy_directory )) {
    Write-Error "Deploy directory '$deploy_directory' does not exist. Aborting."
    exit 1
}

if ( (Get-ChildItem $deploy_directory | Measure-Object).Count -eq 0 -and -not $allow_empty ) {
    Write-Error "Deploy directory '$deploy_directory' is empty. Aborting. If you're sure you want to deploy an empty tree, use the -allow_empty flag." 
    exit 1
}

disable_expanded_output

#enable_expanded_output
write-host "$git fetch --force $repo ${deploy_branch}:$deploy_branch"
&$git fetch --force $repo "${deploy_branch}:$deploy_branch"
enable_expanded_output


#make deploy_branch the current branch
&$git symbolic-ref HEAD "refs/heads/$deploy_branch"

#put the previously committed contents of deploy_branch branch into the index
&$git --work-tree "$deploy_directory" reset --mixed --quiet

&$git --work-tree "$deploy_directory" add --all

#set +o errexit
&$git --work-tree $deploy_directory diff --exit-code --quiet HEAD
#set -o errexit

switch ($LastExitCode) {
    0 {write-host "No changes to files in $deploy_directory. Skipping commit."}
    1 {
        set_user_id
        &$git --work-tree "$deploy_directory" commit -m "publish: $commit_title`n`n generated from commit $commit_hash"

        disable_expanded_output
        #--quiet is important here to avoid outputting the repo URL, which may contain a secret token
        &$git push --quiet $repo $deploy_branch
        enable_expanded_output
       }
    default {
        write-host "git diff exited with code $diff. Aborting. Staying on branch $deploy_branch so you can debug. `n`n To switch back to master, use: git symbolic-ref HEAD refs/heads/master && git reset --mixed"
        exit $diff
       }
}

restore_head
