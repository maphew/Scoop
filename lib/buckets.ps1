$bucketsdir = "$scoopdir\buckets"

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

function Get-AllowedBucket {
    <#
    .SYNOPSIS
        List buckets allowed by managed catalog configuration.
    .DESCRIPTION
        Accepts a JSON array of names or a comma-separated string (the only form
        `scoop config` can write). Non-string values are ignored. Returns an empty
        array when the setting is absent, which means no managed catalog is active.
    #>
    $configured = get_config ALLOWEDBUCKETS
    if ($null -eq $configured) { return @() }
    $names = foreach ($entry in @($configured)) {
        if ($entry -is [string]) {
            foreach ($name in $entry.Split(',')) {
                $name = $name.Trim()
                if ($name) { $name }
            }
        }
    }
    return @($names)
}

function Test-ManagedCatalogEnabled {
    return @(Get-AllowedBucket).Length -gt 0
}

function Test-BucketAllowed($Name) {
    $allowedBuckets = @(Get-AllowedBucket)
    return !$allowedBuckets.Length -or $Name -in $allowedBuckets
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
    $allowedBuckets = @(Get-AllowedBucket)
    $bucketNames = [System.Collections.Generic.List[String]]@(
        (Get-ChildItem -Path $bucketsdir -Directory).Name |
            Where-Object { $_ -and (!$allowedBuckets.Length -or $_ -in $allowedBuckets) }
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
