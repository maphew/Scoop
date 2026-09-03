BeforeAll {
    . "$PSScriptRoot\Scoop-TestLib.ps1"
    . "$PSScriptRoot\..\lib\core.ps1"
    . "$PSScriptRoot\..\lib\buckets.ps1"
    . "$PSScriptRoot\..\lib\manifest.ps1"
    . "$PSScriptRoot\..\lib\versions.ps1"

    $scoopdir = Join-Path ([IO.Path]::GetTempPath()) "scoop-managed-$([Guid]::NewGuid())"
    $bucketsdir = Join-Path $scoopdir 'buckets'
    $envBucket = Join-Path $bucketsdir 'ENV'
    $publicBucket = Join-Path $bucketsdir 'public'
    $workspace = Join-Path $scoopdir 'workspace'
    $installDir = Join-Path $scoopdir 'apps\qgis\0.9'
    New-Item $envBucket, $publicBucket, $workspace, $installDir -ItemType Directory -Force | Out-Null
    '{ "version": "1.0", "url": "https://example.test/env.zip", "hash": "env" }' |
        Set-Content (Join-Path $envBucket 'qgis.json')
    '{ "version": "2.0", "url": "https://example.test/public.zip", "hash": "public" }' |
        Set-Content (Join-Path $publicBucket 'qgis.json')
    '{ "version": "3.0", "url": "https://example.test/generated.zip", "hash": "generated" }' |
        Set-Content (Join-Path $workspace 'qgis.json')
    '{ "version": "0.9", "url": "https://example.test/installed.zip", "hash": "installed" }' |
        Set-Content (Join-Path $installDir 'manifest.json')
}

AfterAll {
    Remove-Item $scoopdir -Recurse -Force
}

Describe 'Managed catalogs' -Tag 'Scoop' {
    BeforeEach {
        $scoopConfig = [PSCustomObject]@{}
    }

    Context 'configuration' {
        It 'allows all buckets when no allowlist is configured' {
            Test-BucketAllowed 'public' | Should -BeTrue
        }

        It 'allows all buckets when the allowlist is empty' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @() }

            Test-ManagedCatalogEnabled | Should -BeFalse
            Test-BucketAllowed 'public' | Should -BeTrue
        }

        It 'accepts a comma-separated allowlist as written by scoop config' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = 'ENV, public,' }

            @(Get-AllowedBucket) | Should -Be @('ENV', 'public')
            Test-BucketAllowed 'public' | Should -BeTrue
            Test-BucketAllowed 'extras' | Should -BeFalse
        }

        It 'ignores non-string allowlist values instead of locking everything out' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = $false }

            Test-ManagedCatalogEnabled | Should -BeFalse
            Test-BucketAllowed 'public' | Should -BeTrue
        }

        It 'falls back to main when the default bucket is unset or blank' {
            Get-DefaultBucket | Should -Be 'main'

            $scoopConfig = [PSCustomObject]@{ defaultBucket = '  ' }
            Get-DefaultBucket | Should -Be 'main'

            $scoopConfig = [PSCustomObject]@{ defaultBucket = ' ENV ' }
            Get-DefaultBucket | Should -Be 'ENV'
            Find-BucketDirectory -Root | Should -Be $envBucket
        }

        It 'fails closed when the bucket change setting is not a boolean' {
            $scoopConfig = [PSCustomObject]@{
                allowedBuckets     = @('ENV')
                allowBucketChanges = 'false'
            }

            add_bucket 'ENV' 'https://example.test/env.git' | Should -Be 3
            rm_bucket 'ENV' | Should -Be 3
            $envBucket | Should -Exist
        }

        It 'fails closed when the public discovery setting is not a boolean' {
            $scoopConfig = [PSCustomObject]@{ allowPublicBucketDiscovery = 'true' }

            Test-PublicBucketDiscoveryAllowed | Should -BeFalse
        }

        It 'keeps the in-memory config unchanged when the config file cannot be written' {
            $configFile = Join-Path $scoopdir 'missing\config.json'
            $scoopConfig = [PSCustomObject]@{ allowedbuckets = @('ENV') }

            set_config allowedbuckets 'public' 6>$null | Out-Null

            @(Get-AllowedBucket) | Should -Be @('ENV')
            Test-BucketAllowed 'public' | Should -BeFalse
            $configFile | Should -Not -Exist
        }
    }

    Context 'local buckets' {
        It 'only lists allowed local buckets' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }

            Test-ManagedCatalogEnabled | Should -BeTrue
            @(Get-LocalBucket) | Should -Be @('ENV')
            Test-BucketAllowed 'ENV' | Should -BeTrue
            Test-BucketAllowed 'public' | Should -BeFalse
        }

        It 'returns an empty list when no local bucket is allowed' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('missing') }

            @(Get-LocalBucket) | Should -BeNullOrEmpty
        }

        It 'returns an empty list when the buckets directory is empty' {
            $bucketsdir = Join-Path $scoopdir 'empty-buckets'
            New-Item $bucketsdir -ItemType Directory -Force | Out-Null

            @(Get-LocalBucket).Count | Should -Be 0
        }

        It 'puts the configured default bucket first' {
            $scoopConfig = [PSCustomObject]@{ defaultBucket = 'PUBLIC' }

            @(Get-LocalBucket)[0] | Should -Be 'public'
        }

        It 'blocks bucket additions and removals when changes are disabled' {
            $scoopConfig = [PSCustomObject]@{
                allowedBuckets     = @('ENV')
                allowBucketChanges = $false
            }

            add_bucket 'ENV' 'https://example.test/env.git' | Should -Be 3
            rm_bucket 'ENV' | Should -Be 3
            $envBucket | Should -Exist
        }

        It 'blocks adding a bucket outside the allowlist' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }

            add_bucket 'public' 'https://example.test/public.git' | Should -Be 3
        }

        It 'still allows removing a bucket outside the allowlist' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            $staleBucket = Join-Path $bucketsdir 'stale'
            New-Item $staleBucket -ItemType Directory -Force | Out-Null

            rm_bucket 'stale' | Should -Be 0
            $staleBucket | Should -Not -Exist
        }
    }

    Context 'manifest resolution' {
        BeforeEach {
            Mock installed { $false }
        }

        It 'resolves unqualified apps from the default bucket first' {
            $scoopConfig = [PSCustomObject]@{
                allowedBuckets = @('ENV', 'public')
                defaultBucket  = 'public'
            }

            $app, $manifest, $bucket, $url = Get-Manifest 'qgis'

            $app | Should -Be 'qgis'
            $manifest.version | Should -Be '2.0'
            $bucket | Should -Be 'public'
            $url | Should -BeNullOrEmpty
        }

        It 'resolves unqualified apps only from allowed buckets' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }

            $app, $manifest, $bucket, $url = Get-Manifest 'qgis'

            $manifest.version | Should -Be '1.0'
            $bucket | Should -Be 'ENV'
        }

        It 'rejects an explicit disallowed bucket' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }

            $app, $manifest, $bucket, $url = Get-Manifest 'public/qgis'

            $app | Should -Be 'qgis'
            $manifest | Should -BeNullOrEmpty
            $bucket | Should -Be 'public'
            $url | Should -BeNullOrEmpty
        }

        It 'rejects standalone URL and local manifests' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            Mock url_manifest { throw 'url_manifest should not be called' }

            $null, $urlManifest, $null, $url = Get-Manifest 'https://example.test/qgis.json'
            $null, $localManifest, $null, $localPath = Get-Manifest (Join-Path $publicBucket 'qgis.json')

            $urlManifest | Should -BeNullOrEmpty
            $url | Should -Be 'https://example.test/qgis.json'
            $localManifest | Should -BeNullOrEmpty
            $localPath | Should -Be (Join-Path $publicBucket 'qgis.json')
        }

        It 'accepts manifest paths that Scoop generated from an allowed bucket' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }

            $null, $bucketManifest, $null, $null = Get-Manifest (Join-Path $envBucket 'qgis.json')
            $null, $workspaceManifest, $null, $null = Get-Manifest (Join-Path $workspace 'qgis.json')

            $bucketManifest.version | Should -Be '1.0'
            $workspaceManifest.version | Should -Be '3.0'
        }

        It 'returns the bucket manifest path for a pinned version from an allowed bucket' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }

            generate_user_manifest 'qgis' 'ENV' '1.0' | Should -Be (Join-Path $envBucket 'qgis.json')
        }

        It 'does not read history or autoupdate for a disallowed bucket' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            Mock Find-HistoricalManifest { throw 'history should not be consulted' }

            generate_user_manifest 'qgis' 'public' '9.9' | Should -BeNullOrEmpty
        }

        It 'blocks update manifest lookup for disallowed sources' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            Mock url_manifest { throw 'url_manifest should not be called' }

            manifest 'qgis' 'public' | Should -BeNullOrEmpty
            manifest 'qgis' $null 'https://example.test/qgis.json' | Should -BeNullOrEmpty
            Should -Invoke url_manifest -Times 0
        }

        It 'allows update manifest lookup from an allowed bucket' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }

            (manifest 'qgis' 'ENV').version | Should -Be '1.0'
        }
    }

    Context 'installed apps' {
        BeforeEach {
            Mock installed { $true }
            Mock Select-CurrentVersion { '0.9' }
            Mock versiondir { $installDir }
            Mock failed { $false }
        }

        It 'falls back to the installed manifest when the recorded URL is no longer allowed' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            '{ "url": "https://example.test/qgis.json" }' | Set-Content (Join-Path $installDir 'install.json')
            Mock url_manifest { throw 'url_manifest should not be called' }

            $app, $manifest, $bucket, $url = Get-Manifest 'qgis'

            $manifest.version | Should -Be '0.9'
            $url | Should -Be 'https://example.test/qgis.json'
        }

        It 'falls back to the installed manifest when the recorded bucket is no longer allowed' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            '{ "bucket": "public" }' | Set-Content (Join-Path $installDir 'install.json')

            $app, $manifest, $bucket, $url = Get-Manifest 'qgis'

            $manifest.version | Should -Be '0.9'
            $bucket | Should -Be 'public'
        }

        It 'reads the bucket manifest when the recorded bucket is allowed' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            '{ "bucket": "ENV" }' | Set-Content (Join-Path $installDir 'install.json')

            $app, $manifest, $bucket, $url = Get-Manifest 'qgis'

            $manifest.version | Should -Be '1.0'
        }

        It 'reports a blocked source in app_status instead of a removed manifest' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            Mock install_info { @{ url = 'https://example.test/qgis.json' } }

            $status = app_status 'qgis' $false

            $status.blocked | Should -BeTrue
            $status.removed | Should -BeFalse
            $status.outdated | Should -BeFalse
            $status.latest_version | Should -Be '0.9'
        }

        It 'reports outdated apps from an allowed bucket in app_status' {
            $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
            Mock install_info { @{ bucket = 'ENV' } }

            $status = app_status 'qgis' $false

            $status.blocked | Should -BeFalse
            $status.removed | Should -BeFalse
            $status.outdated | Should -BeTrue
            $status.latest_version | Should -Be '1.0'
        }
    }
}
