param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$atlasDirectory = Join-Path $ProjectRoot 'assets\markers'
$outputDirectory = Join-Path $atlasDirectory 'directional'
$colors = @('blue', 'yellow', 'purple', 'red', 'green', 'orange')
$directions = @('n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw')

# The generated atlases share an identical 1774x887 layout. The source views
# are ordered here by the train's actual direction of travel, using its visible
# nose/tail, rather than by their placement in the generated sheet.
$sourceRects = @(
    [System.Drawing.Rectangle]::new(30, 430, 275, 457),
    [System.Drawing.Rectangle]::new(1350, 0, 424, 440),
    [System.Drawing.Rectangle]::new(775, 600, 600, 190),
    [System.Drawing.Rectangle]::new(1350, 430, 424, 457),
    [System.Drawing.Rectangle]::new(30, 0, 275, 440),
    [System.Drawing.Rectangle]::new(285, 0, 535, 440),
    [System.Drawing.Rectangle]::new(715, 180, 640, 190),
    [System.Drawing.Rectangle]::new(285, 430, 535, 457)
)

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

foreach ($color in $colors) {
    $atlas = Join-Path $atlasDirectory "metro_train_directions_$color.png"
    if (-not (Test-Path -LiteralPath $atlas)) {
        throw "Missing directional train atlas: $atlas"
    }

    $source = [System.Drawing.Bitmap]::FromFile($atlas)
    try {
        if ($source.Width -ne 1774 -or $source.Height -ne 887) {
            throw "Unexpected atlas dimensions for $atlas`: $($source.Width)x$($source.Height)"
        }

        for ($index = 0; $index -lt $directions.Count; $index++) {
            $sourceRect = $sourceRects[$index]
            $output = [System.Drawing.Bitmap]::new(
                512,
                512,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
            )
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($output)
                try {
                    $graphics.Clear([System.Drawing.Color]::Transparent)
                    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

                    $available = 456.0
                    $scale = [Math]::Min(
                        $available / $sourceRect.Width,
                        $available / $sourceRect.Height
                    )
                    $width = $sourceRect.Width * $scale
                    $height = $sourceRect.Height * $scale
                    $destination = [System.Drawing.RectangleF]::new(
                        (512.0 - $width) / 2.0,
                        (512.0 - $height) / 2.0,
                        $width,
                        $height
                    )
                    $graphics.DrawImage(
                        $source,
                        $destination,
                        $sourceRect,
                        [System.Drawing.GraphicsUnit]::Pixel
                    )
                }
                finally {
                    $graphics.Dispose()
                }

                $fileName = "metro_train_3d_${color}_$($directions[$index]).png"
                $outputPath = Join-Path $outputDirectory $fileName
                $output.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $output.Dispose()
            }
        }
    }
    finally {
        $source.Dispose()
    }
}

Write-Output "Generated $($colors.Count * $directions.Count) normalized directional train sprites in $outputDirectory"
