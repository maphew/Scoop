BeforeAll {
    . "$PSScriptRoot\Scoop-TestLib.ps1"
    . "$PSScriptRoot\..\lib\core.ps1"
    . "$PSScriptRoot\..\lib\buckets.ps1"
    . "$PSScriptRoot\..\lib\manifest.ps1"

    $scoopdir = Join-Path ([IO.Path]::GetTempPath()) "scoop-managed-$([Guid]::NewGuid())"
    $bucketsdir = Join-Path $scoopdir 'buckets'
    $envBucket = Join-Path $bucketsdir 'ENV'
    $publicBucket = Join-Path $bucketsdir 'public'
    New-Item $envBucket, $publicBucket -ItemType Directory -Force | Out-Null
    '{ "version": "1.0", "url": "https://example.test/env.zip", "hash": "env" }' |
        Set-Content (Join-Path $envBucket 'qgis.json')
    '{ "version": "2.0", "url": "https://example.test/public.zip", "hash": "public" }' |
        Set-Content (Join-Path $publicBucket 'qgis.json')
}

AfterAll {
    Remove-Item $scoopdir -Recurse -Force
}

Describe 'Managed catalogs' -Tag 'Scoop' {
    BeforeEach {
        $scoopConfig = [PSCustomObject]@{}
    }

    It 'allows all buckets when no allowlist is configured' {
        Test-BucketAllowed 'public' | Should -BeTrue
    }

    It 'only lists allowed local buckets' {
        $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }

        @(Get-LocalBucket) | Should -Be @('ENV')
        Test-BucketAllowed 'ENV' | Should -BeTrue
        Test-BucketAllowed 'public' | Should -BeFalse
    }

    It 'returns an empty list when no local bucket is allowed' {
        $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('missing') }

        @(Get-LocalBucket) | Should -BeNullOrEmpty
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

    It 'resolves unqualified apps from the allowed default bucket' {
        $scoopConfig = [PSCustomObject]@{
            allowedBuckets = @('ENV')
            defaultBucket  = 'ENV'
        }
        Mock installed { $false }

        $app, $manifest, $bucket, $url = Get-Manifest 'qgis'

        $app | Should -Be 'qgis'
        $manifest.version | Should -Be '1.0'
        $bucket | Should -Be 'ENV'
        $url | Should -BeNullOrEmpty
    }

    It 'rejects an explicit disallowed bucket' {
        $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
        Mock installed { $false }

        $app, $manifest, $bucket, $url = Get-Manifest 'public/qgis'

        $app | Should -Be 'qgis'
        $manifest | Should -BeNullOrEmpty
        $bucket | Should -Be 'public'
        $url | Should -BeNullOrEmpty
    }

    It 'rejects standalone URL and local manifests' {
        $scoopConfig = [PSCustomObject]@{ allowedBuckets = @('ENV') }
        Mock installed { $false }
        Mock url_manifest { throw 'url_manifest should not be called' }

        $null, $urlManifest, $null, $url = Get-Manifest 'https://example.test/qgis.json'
        $null, $localManifest, $null, $localPath = Get-Manifest (Join-Path $publicBucket 'qgis.json')

        $urlManifest | Should -BeNullOrEmpty
        $url | Should -Be 'https://example.test/qgis.json'
        $localManifest | Should -BeNullOrEmpty
        $localPath | Should -Be (Join-Path $publicBucket 'qgis.json')
    }
}
