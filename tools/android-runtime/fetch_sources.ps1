$ErrorActionPreference = "Stop"

$runtimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$downloadsDir = Join-Path $runtimeDir "downloads"
$sourcesDir = Join-Path $runtimeDir "sources"

New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
New-Item -ItemType Directory -Force -Path $sourcesDir | Out-Null

# Upstream CDNs (notably ftp.gnu.org) intermittently answer 502/503/504.
# Each item lists ordered fallback mirrors; the SHA256 below still pins the
# exact bytes, so a mirror can supply the download but cannot alter it.
$items = @(
    @{
        Name = "busybox-1.38.0"
        Urls = @(
            "https://busybox.net/downloads/busybox-1.38.0.tar.bz2"
        )
        Archive = "busybox-1.38.0.tar.bz2"
        Sha256 = "34F9EA6FF8636F2C9241153B9114EEFA9E65674A45318AE1EF95BB5F31C53BB2"
        Extracted = "busybox-1.38.0"
    },
    @{
        Name = "termux-proot-v5.1.107.78"
        Urls = @(
            "https://github.com/termux/proot/archive/refs/tags/v5.1.107.78.tar.gz"
        )
        Archive = "termux-proot-v5.1.107.78.tar.gz"
        Sha256 = "F3377BA49DCD833370420C34C5081B4C243ECBB85B2A9881A4F4586012599AFA"
        Extracted = "proot-5.1.107.78"
    },
    @{
        Name = "talloc-2.4.3"
        # samba.org serves 503 for the whole host often enough that this archive
        # is effectively unavailable. tools/android-runtime/vendor/talloc is the
        # committed fallback and is what the build normally uses; this entry is
        # only attempted so an upstream-fetched tree still wins when it is
        # reachable. Optional: failing here does not stop the build.
        Urls = @(
            "https://www.samba.org/ftp/talloc/talloc-2.4.3.tar.gz"
        )
        Archive = "talloc-2.4.3.tar.gz"
        Sha256 = "DC46C40B9F46BB34DD97FE41F548B0E8B247B77A918576733C528E83ABD854DD"
        Extracted = "talloc-2.4.3"
        Optional = $true
    },
    @{
        Name = "bash-5.2.37"
        # Fastest mirror first: ftp.gnu.org took 447s here and USTC rejects
        # GitHub-runner requests with 403, so it is intentionally omitted.
        Urls = @(
            "https://mirror.nju.edu.cn/gnu/bash/bash-5.2.37.tar.gz"
            "https://mirrors.kernel.org/gnu/bash/bash-5.2.37.tar.gz"
            "https://ftp.gnu.org/gnu/bash/bash-5.2.37.tar.gz"
        )
        Archive = "bash-5.2.37.tar.gz"
        Sha256 = "9599B22ECD1D5787AD7D3B7BF0C59F312B3396D1E281175DD1F8A4014DA621FF"
        Extracted = "bash-5.2.37"
    }
)

# Downloads one archive, trying each mirror and retrying transport failures.
function Get-Archive([string]$name, [string[]]$urls, [string]$archivePath) {
    $lastError = $null
    foreach ($url in $urls) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Write-Host "Downloading $name from $url (attempt $attempt)"
                Invoke-WebRequest -Uri $url -OutFile $archivePath -MaximumRedirection 5 -TimeoutSec 300
                return
            } catch {
                $lastError = $_
                Write-Warning "$url failed on attempt ${attempt}: $($_.Exception.Message)"
                if ($attempt -lt 3) { Start-Sleep -Seconds (5 * $attempt) }
            }
        }
    }
    throw "Unable to download $name from any mirror. Last error: $($lastError.Exception.Message)"
}

foreach ($item in $items) {
    $archivePath = Join-Path $downloadsDir $item.Archive
    try {
        Get-Archive $item.Name $item.Urls $archivePath
    } catch {
        if ($item.Optional) {
            Write-Warning "Skipping optional source $($item.Name): $($_.Exception.Message)"
            continue
        }
        throw
    }

    $actualSha256 = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash.ToUpperInvariant()
    if ($actualSha256 -ne $item.Sha256) {
        throw "$($item.Archive) SHA256 mismatch: $actualSha256"
    }

    $extractPath = Join-Path $sourcesDir $item.Extracted
    if (Test-Path $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force
    }

    tar -xf $archivePath -C $sourcesDir
}
