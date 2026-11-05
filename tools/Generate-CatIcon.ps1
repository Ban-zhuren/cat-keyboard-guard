param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

function New-CatArtwork([int]$size) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bitmap.SetResolution(96, 96)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.ScaleTransform(($size / 256.0), ($size / 256.0))

    $outline = [System.Drawing.ColorTranslator]::FromHtml('#263238')
    $fur = [System.Drawing.ColorTranslator]::FromHtml('#F2AA3C')
    $furShade = [System.Drawing.ColorTranslator]::FromHtml('#D98A24')
    $innerEar = [System.Drawing.ColorTranslator]::FromHtml('#E78386')
    $muzzle = [System.Drawing.ColorTranslator]::FromHtml('#FFF3D8')
    $nose = [System.Drawing.ColorTranslator]::FromHtml('#CF626D')

    $outlineBrush = New-Object System.Drawing.SolidBrush($outline)
    $furBrush = New-Object System.Drawing.SolidBrush($fur)
    $innerEarBrush = New-Object System.Drawing.SolidBrush($innerEar)
    $muzzleBrush = New-Object System.Drawing.SolidBrush($muzzle)
    $noseBrush = New-Object System.Drawing.SolidBrush($nose)
    $outlinePen = New-Object System.Drawing.Pen($outline, 10)
    $detailPen = New-Object System.Drawing.Pen($outline, 7)
    $stripePen = New-Object System.Drawing.Pen($furShade, 8)
    $mouthPen = New-Object System.Drawing.Pen($outline, 5)

    foreach ($pen in @($outlinePen, $detailPen, $stripePen, $mouthPen)) {
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    }

    try {
        $leftEar = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(44, 83)),
            (New-Object System.Drawing.PointF(37, 19)),
            (New-Object System.Drawing.PointF(101, 57))
        )
        $rightEar = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(155, 57)),
            (New-Object System.Drawing.PointF(219, 19)),
            (New-Object System.Drawing.PointF(212, 83))
        )
        $graphics.FillPolygon($furBrush, $leftEar)
        $graphics.DrawPolygon($outlinePen, $leftEar)
        $graphics.FillPolygon($furBrush, $rightEar)
        $graphics.DrawPolygon($outlinePen, $rightEar)

        $leftInner = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(51, 64)),
            (New-Object System.Drawing.PointF(48, 38)),
            (New-Object System.Drawing.PointF(79, 57))
        )
        $rightInner = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(177, 57)),
            (New-Object System.Drawing.PointF(208, 38)),
            (New-Object System.Drawing.PointF(205, 64))
        )
        $graphics.FillPolygon($innerEarBrush, $leftInner)
        $graphics.FillPolygon($innerEarBrush, $rightInner)

        $graphics.FillEllipse($furBrush, 31, 43, 194, 190)
        $graphics.DrawEllipse($outlinePen, 31, 43, 194, 190)

        $graphics.DrawLine($stripePen, 102, 58, 108, 80)
        $graphics.DrawLine($stripePen, 128, 54, 128, 79)
        $graphics.DrawLine($stripePen, 154, 58, 148, 80)

        $graphics.FillEllipse($outlineBrush, 76, 103, 24, 34)
        $graphics.FillEllipse($outlineBrush, 156, 103, 24, 34)
        $graphics.FillEllipse([System.Drawing.Brushes]::White, 82, 108, 7, 9)
        $graphics.FillEllipse([System.Drawing.Brushes]::White, 162, 108, 7, 9)

        $graphics.FillEllipse($muzzleBrush, 87, 144, 45, 43)
        $graphics.FillEllipse($muzzleBrush, 124, 144, 45, 43)

        $noseShape = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(116, 153)),
            (New-Object System.Drawing.PointF(140, 153)),
            (New-Object System.Drawing.PointF(128, 168))
        )
        $graphics.FillPolygon($noseBrush, $noseShape)
        $graphics.DrawPolygon($mouthPen, $noseShape)
        $graphics.DrawLine($mouthPen, 128, 168, 128, 177)
        $graphics.DrawArc($mouthPen, 107, 166, 21, 22, 10, 80)
        $graphics.DrawArc($mouthPen, 128, 166, 21, 22, 90, 80)

        $graphics.DrawLine($mouthPen, 91, 159, 49, 151)
        $graphics.DrawLine($mouthPen, 91, 170, 45, 171)
        $graphics.DrawLine($mouthPen, 93, 181, 52, 191)
        $graphics.DrawLine($mouthPen, 165, 159, 207, 151)
        $graphics.DrawLine($mouthPen, 165, 170, 211, 171)
        $graphics.DrawLine($mouthPen, 163, 181, 204, 191)
    }
    finally {
        $outlineBrush.Dispose()
        $furBrush.Dispose()
        $innerEarBrush.Dispose()
        $muzzleBrush.Dispose()
        $noseBrush.Dispose()
        $outlinePen.Dispose()
        $detailPen.Dispose()
        $stripePen.Dispose()
        $mouthPen.Dispose()
        $graphics.Dispose()
    }

    return $bitmap
}

function Convert-BitmapToPngBytes([System.Drawing.Bitmap]$bitmap) {
    $stream = New-Object System.IO.MemoryStream
    try {
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    }
    finally {
        $stream.Dispose()
    }
}

$previewPath = Join-Path $OutputDirectory 'cat-head.png'
$preview = New-CatArtwork 512
try {
    $preview.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $preview.Dispose()
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$images = @()
foreach ($size in $sizes) {
    $bitmap = New-CatArtwork $size
    try {
        $images += ,(Convert-BitmapToPngBytes $bitmap)
    }
    finally {
        $bitmap.Dispose()
    }
}

$iconPath = Join-Path $OutputDirectory 'cat-head.ico'
$file = [System.IO.File]::Open($iconPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
$writer = New-Object System.IO.BinaryWriter($file)
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$images.Count)

    $offset = 6 + (16 * $images.Count)
    for ($index = 0; $index -lt $images.Count; $index++) {
        $size = $sizes[$index]
        $dimension = if ($size -eq 256) { [byte]0 } else { [byte]$size }
        $writer.Write($dimension)
        $writer.Write($dimension)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$images[$index].Length)
        $writer.Write([UInt32]$offset)
        $offset += $images[$index].Length
    }

    foreach ($image in $images) {
        $writer.Write([byte[]]$image)
    }
}
finally {
    $writer.Dispose()
    $file.Dispose()
}

Write-Output $previewPath
Write-Output $iconPath
