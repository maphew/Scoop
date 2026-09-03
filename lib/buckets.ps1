$bucketsdir = "$scoopdir\buckets"
$bucketOriginCache = @{} # bucket root -> normalised remote.origin.url, filled by Get-BucketOrigin

function Find-BucketDirectory {
    <#
    .DESCRIPTION
        Return full path for bucket with given name.
        Main bucket will be returned as default.
    .PARAMETER Name
        Name of bucket.
    .PARAMETER Root
        Root folder of bucket repository will be returned instead of 'bucket' subdirectory (if exists).
    #>
    param(
        [string] $Name,
        [switch] $Root
    )

    # Handle info passing empty string as bucket ($install.bucket)
    if (($null -eq $Name) -or ($Name -eq '')) {
        $Name = Get-DefaultBucket
    }
    $bucket = "$bucketsdir\$Name"

    if ((Test-Path "$bucket\bucket") -and !$Root) {
        $bucket = "$bucket\bucket"
    }

    return $bucket
}

function bucketdir($name) {
    Show-DeprecatedWarning $MyInvocation 'Find-BucketDirectory'

    return Find-BucketDirectory $name
}

function known_bucket_repos {
    $json = "$PSScriptRoot\..\buckets.json"

    return Get-Content $json -Raw | ConvertFrom-Json -ErrorAction stop
}

function known_bucket_repo($name) {
    $buckets = known_bucket_repos
    $buckets.$name
}

function known_buckets {
    known_bucket_repos | ForEach-Object { $_.PSObject.Properties | Select-Object -Expand 'name' }
}

# ---------------------------------------------------------------------------
# Managed catalogs (ScoopInstaller/Scoop#6729)
#
# Scope. The allowedBuckets, allowBucketChanges, allowPublicBucketDiscovery and
# defaultBucket settings let an administrator restrict *new* installations to an
# approved set of buckets. They are policy, not a security boundary: anything
# Scoop reads from a user-writable directory (config.json, buckets\, workspace\)
# can be forged by that user, and $env:SCOOP can point Scoop at another root.
#
# Decisions that shape the code below:
# - Off by default. An absent or empty allowlist changes no behaviour.
# - Names are matched against bucket directory names. A name may be pinned to a
#   repository ("ENV": "https://..." in JSON, or ENV=https://... on the CLI); a
#   local clone must then have that origin and add_bucket refuses any other
#   repository. This stops accidental rebinding, not a determined user.
# - Boolean flags fail closed: only a real JSON true enables them.
# - Read-only commands keep working on apps installed before the policy from a
#   source that is now rejected; they fall back to the installed manifest and
#   are reported as blocked, never re-fetched or updated.
# - Local manifest paths are trusted only inside an allowed bucket or the
#   workspace directory, which is where Scoop writes generated manifests.
# - rm_bucket is gated by allowBucketChanges only, so a stale bucket outside
#   the allowlist can always be removed.
# - The SQLite cache is reconciled with the allowlist by set_config and
#   Sync-Bucket (see Sync-ScoopDB), because search and history read from it.
#
# To make this enforceable, policy and trusted content must both live where the
# user cannot write. The winget-style shape would be:
#   1. read these settings from HKLM\SOFTWARE\Policies\Scoop (Group Policy,
#      administrators only) with precedence over config.json and $env:SCOOP;
#   2. clone allowed buckets under the global directory (ProgramData\scoop),
#      updated by an administrator task, with user `scoop update` skipping them.
# Neither is implemented; both need maintainer agreement on the policy source.
# ---------------------------------------------------------------------------

function Get-AllowedBucketEntry {
    <#
    .SYNOPSIS
        Parse the allowedBuckets setting into @{ Name; Repo } entries.
    .DESCRIPTION
        Accepts a JSON object (name -> repository URL), a JSON array of names, or a
        comma-separated string of `name` or `name=repo` items (the only form
        `scoop config` can write). Non-string values are ignored. Returns an empty
        array when the setting is absent, which means no managed catalog is active.
    #>
    $configured = get_config ALLOWEDBUCKETS
    if ($null -eq $configured) { return @() }
    $entries = [System.Collections.Generic.List[hashtable]]::new()
    if ($configured -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $configured.PSObject.Properties) {
            $name = $property.Name.Trim()
            $repo = if ($property.Value -is [string]) { $property.Value.Trim() }
            if ($name) { $entries.Add(@{ Name = $name; Repo = $repo }) }
        }
        return @($entries)
    }
    foreach ($value in @($configured)) {
        if ($value -isnot [string]) { continue }
        foreach ($item in $value.Split(',')) {
            $name, $repo = $item.Split('=', 2)
            $name = $name.Trim()
            $repo = if ($repo) { $repo.Trim() }
            if ($name) { $entries.Add(@{ Name = $name; Repo = $repo }) }
        }
    }
    return @($entries)
}

function Get-AllowedBucket {
    <#
    .SYNOPSIS
        List bucket names allowed by managed catalog configuration.
    #>
    return @(Get-AllowedBucketEntry | ForEach-Object { $_.Name })
}

function Get-AllowedBucketRepo($Name) {
    <#
    .SYNOPSIS
        Repository URL the allowlist pins the bucket to, or $null when only the name is listed.
    #>
    $entry = Get-AllowedBucketEntry | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($entry -and $entry.Repo) { return $entry.Repo }
    return $null
}

function Get-BucketOrigin($Name) {
    <#
    .SYNOPSIS
        Normalised remote.origin.url of a local bucket clone, cached per process.
        $null when the bucket is not a git repository or git is unavailable.
    #>
    $dir = Find-BucketDirectory $Name -Root
    if ($bucketOriginCache.ContainsKey($dir)) { return $bucketOriginCache[$dir] }
    $origin = $null
    if ((Test-Path (Join-Path $dir '.git')) -and (Test-GitAvailable)) {
        $remote = Invoke-Git -Path $dir -ArgumentList @('config', '--get', 'remote.origin.url')
        if ($remote) { $origin = Convert-RepositoryUri -Uri "$remote" }
    }
    $bucketOriginCache[$dir] = $origin
    return $origin
}

function Test-ManagedCatalogEnabled {
    return @(Get-AllowedBucketEntry).Length -gt 0
}

function Test-BucketAllowed($Name) {
    $entries = @(Get-AllowedBucketEntry)
    if (!$entries.Length) { return $true }
    $entry = $entries | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if (!$entry) { return $false }
    if (!$entry.Repo) { return $true }
    # The name is pinned to a repository. A clone on disk must have that origin;
    # a bucket not on disk yet passes here and add_bucket verifies the repository.
    if (!(Test-Path (Find-BucketDirectory $Name -Root))) { return $true }
    $required = Convert-RepositoryUri -Uri $entry.Repo
    return [bool]$required -and (Get-BucketOrigin $Name) -eq $required
}

function Get-DefaultBucket {
    <#
    .SYNOPSIS
        Name of the bucket used when an app has no bucket qualifier. Defaults to 'main'.
    #>
    $name = get_config DEFAULTBUCKET
    if ($name -is [string] -and ![String]::IsNullOrWhiteSpace($name)) { return $name.Trim() }
    return 'main'
}

function Test-ManagedCatalogFlag($Key) {
    # Fail closed: only a real boolean $true enables the behaviour, so a hand-edited
    # config such as "allowBucketChanges": "true" does not silently unlock it.
    $setting = get_config $Key $true
    return $setting -is [bool] -and $setting
}

function Test-BucketChangeAllowed {
    return Test-ManagedCatalogFlag ALLOWBUCKETCHANGES
}

function Test-PublicBucketDiscoveryAllowed {
    return Test-ManagedCatalogFlag ALLOWPUBLICBUCKETDISCOVERY
}

function Get-BucketAddHint($Name) {
    # Known buckets need no repository argument.
    if ($Name -in (known_buckets)) { return "scoop bucket add $Name" }
    return "scoop bucket add $Name <repo>"
}

function apps_in_bucket($dir) {
    return (Get-ChildItem $dir -Filter '*.json' -Recurse).BaseName
}

function Get-LocalBucket {
    <#
    .SYNOPSIS
        List all local buckets.
    #>
    $managed = Test-ManagedCatalogEnabled
    $bucketNames = [System.Collections.Generic.List[String]]@(
        (Get-ChildItem -Path $bucketsdir -Directory).Name |
            Where-Object { $_ -and (!$managed -or (Test-BucketAllowed $_)) }
    )
    if ($bucketNames.Count -eq 0) {
        return @() # Return a zero-length list instead of $null.
    }
    # Known buckets are listed first, and the default bucket before those.
    # Walk the priority list backwards so the first entry ends up at the front.
    $priority = @(Get-DefaultBucket) + @(known_buckets)
    for ($i = $priority.Count - 1; $i -ge 0 ; $i--) {
        $wanted = $priority[$i]
        $name = $null
        foreach ($candidate in $bucketNames) {
            if ($candidate -ieq $wanted) { $name = $candidate; break }
        }
        if ($name) {
            [void]$bucketNames.Remove($name)
            $bucketNames.Insert(0, $name)
        }
    }
    return $bucketNames
}

function buckets {
    Show-DeprecatedWarning $MyInvocation 'Get-LocalBucket'

    return Get-LocalBucket
}

function Convert-RepositoryUri {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [String] $Uri
    )

    process {
        # https://git-scm.com/docs/git-clone#_git_urls
        # https://regex101.com/r/xGmwRr/1
        if ($Uri -match '(?:@|/{1,3})(?:www\.|.*@)?(?<provider>[^/]+?)(?::\d+)?[:/](?<user>.+)/(?<repo>.+?)(?:\.git)?/?$') {
            $Matches.provider, $Matches.user, $Matches.repo -join '/'
        } else {
            error "$Uri is not a valid Git URL!"
            error "Please see https://git-scm.com/docs/git-clone#_git_urls for valid ones."
            return $null
        }
    }
}

function list_buckets {
    $buckets = @()
    Get-LocalBucket | ForEach-Object {
        $bucket = [Ordered]@{ Name = $_ }
        $path = Find-BucketDirectory $_ -Root
        if ((Test-Path (Join-Path $path '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
            $bucket.Source = Invoke-Git -Path $path -ArgumentList @('config', 'remote.origin.url')
            $bucket.Updated = Invoke-Git -Path $path -ArgumentList @('log', '--format=%aI', '-n', '1') | Get-Date
        } else {
            $bucket.Source = friendly_path $path
            $bucket.Updated = (Get-Item "$path\bucket" -ErrorAction SilentlyContinue).LastWriteTime
        }
        $bucket.Manifests = Get-ChildItem -Path "$path\bucket" -Filter "*.json" -File -Force -Recurse -ErrorAction SilentlyContinue |
                Measure-Object | Select-Object -ExpandProperty Count
        $buckets += [PSCustomObject]$bucket
    }
    ,$buckets
}

function add_bucket($name, $repo) {
    if (!(Test-BucketChangeAllowed)) {
        error 'Bucket changes are disabled by managed catalog configuration.'
        return 3
    }
    if (!(Test-BucketAllowed $name)) {
        error "Bucket '$name' is not allowed by managed catalog configuration."
        return 3
    }
    if (!(Test-GitAvailable)) {
        error "Git is required for buckets. Run 'scoop install git' and try again."
        return 1
    }

    $dir = Find-BucketDirectory $name -Root
    if (Test-Path $dir) {
        warn "The '$name' bucket already exists. To add this bucket again, first remove it by running 'scoop bucket rm $name'."
        return 2
    }

    $uni_repo = Convert-RepositoryUri -Uri $repo
    if ($null -eq $uni_repo) {
        return 1
    }
    $requiredRepo = Get-AllowedBucketRepo $name
    if ($requiredRepo -and (Convert-RepositoryUri -Uri $requiredRepo) -ne $uni_repo) {
        error "Bucket '$name' must be added from '$requiredRepo' by managed catalog configuration."
        return 3
    }
    foreach ($bucket in Get-LocalBucket) {
        if (Test-Path -Path "$bucketsdir\$bucket\.git") {
            $remote = Invoke-Git -Path "$bucketsdir\$bucket" -ArgumentList @('config', '--get', 'remote.origin.url')
            if ((Convert-RepositoryUri -Uri $remote) -eq $uni_repo) {
                warn "Bucket $bucket already exists for $repo"
                return 2
            }
        }
    }

    Write-Host 'Checking repo... ' -NoNewline
    $out = Invoke-Git -ArgumentList @('ls-remote', $repo) 2>&1
    if ($LASTEXITCODE -ne 0) {
        error "'$repo' doesn't look like a valid git repository`n`nError given:`n$out"
        return 1
    }
    ensure $bucketsdir | Out-Null
    $dir = ensure $dir
    $out = Invoke-Git -ArgumentList @('clone', $repo, $dir, '-q')
    if ($LASTEXITCODE -ne 0) {
        error "Failed to clone '$repo' to '$dir'.`n`nError given:`n$out`n`nPlease check the repository URL or network connection and try again."
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        return 1
    }
    Write-Host 'OK.'
    $bucketOriginCache.Remove($dir)
    if (get_config USE_SQLITE_CACHE) {
        info 'Updating cache...'
        Set-ScoopDB -Path (Get-ChildItem (Find-BucketDirectory $name) -Filter '*.json' -Recurse).FullName
    }
    success "The $name bucket was added successfully."
    return 0
}

function rm_bucket($name) {
    # Removal is only gated by allowBucketChanges: deleting a bucket outside the
    # allowlist moves the installation towards compliance, so it stays possible.
    if (!(Test-BucketChangeAllowed)) {
        error 'Bucket changes are disabled by managed catalog configuration.'
        return 3
    }
    $dir = Find-BucketDirectory $name -Root
    if (!(Test-Path $dir)) {
        error "'$name' bucket not found."
        return 1
    }

    Remove-Item $dir -Recurse -Force -ErrorAction Stop
    $bucketOriginCache.Remove($dir)
    if (get_config USE_SQLITE_CACHE) {
        info 'Updating cache...'
        Remove-ScoopDBItem -Bucket $name
    }
    success "The $name bucket was removed successfully."
    return 0
}

function new_issue_msg($app, $bucket, $title, $body) {
    $app, $manifest, $bucket, $url = Get-Manifest "$bucket/$app"
    $url = known_bucket_repo $bucket
    $bucket_path = "$bucketsdir\$bucket"

    if ((Test-Path $bucket_path) -and (Test-GitAvailable)) {
        $remote = Invoke-Git -Path $bucket_path -ArgumentList @('config', '--get', 'remote.origin.url')
        # Support ssh and http syntax
        # git@PROVIDER:USER/REPO.git
        # https://PROVIDER/USER/REPO.git
        $remote -match '(@|:\/\/)(?<provider>.+)[:/](?<user>.*)\/(?<repo>.*)(\.git)?$' | Out-Null
        $url = "https://$($Matches.Provider)/$($Matches.User)/$($Matches.Repo)"
    }

    if (!$url) { return 'Please contact the bucket maintainer!' }

    # Print only github repositories
    if ($url -like '*github*') {
        $title = [System.Web.HttpUtility]::UrlEncode("$app@$($manifest.version): $title")
        $body = [System.Web.HttpUtility]::UrlEncode($body)
        $url = $url -replace '\.git$', ''
        $url = "$url/issues/new?title=$title"
        if ($body) {
            $url += "&body=$body"
        }
    }

    $msg = "`nPlease try again or create a new issue by using the following link and paste your console output:"
    return "$msg`n$url"
}
