#Requires -Version 5.1
# Copyright (c) 2026 Xiaohei Wu. xiaohei.wu@whu.edu.cn
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
[xml]$document = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'App.xaml'))
$ns = New-Object Xml.XmlNamespaceManager($document.NameTable)
$ns.AddNamespace('p', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
$ns.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
$logoNode = $document.SelectSingleNode('//p:DrawingImage[@x:Key="AppLogo"]', $ns)
$logo = [Windows.Markup.XamlReader]::Parse($logoNode.OuterXml)
$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$frames = @()
foreach ($size in ($sizes + 512)) {
    $visual = New-Object Windows.Media.DrawingVisual
    $context = $visual.RenderOpen()
    $context.DrawImage($logo, (New-Object Windows.Rect(0, 0, $size, $size)))
    $context.Close()
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($size, $size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = New-Object IO.MemoryStream
    $encoder.Save($stream)
    if ($size -eq 512) { [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'logo.png'), $stream.ToArray()) }
    else { $frames += ,([pscustomobject]@{Size=$size; Bytes=$stream.ToArray()}) }
    $stream.Dispose()
}
$output = [IO.File]::Create((Join-Path $PSScriptRoot 'logo.ico'))
$writer = New-Object IO.BinaryWriter($output)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    foreach ($frame in $frames) {
        $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
        $offset += $frame.Bytes.Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
}
finally { $writer.Dispose(); $output.Dispose() }
$svg = @('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="OpenCode Sessions">', '<title>OpenCode Sessions</title>', '<!-- Copyright (c) 2026 Xiaohei Wu. xiaohei.wu@whu.edu.cn -->')
foreach ($geometry in $logoNode.SelectNodes('.//p:GeometryDrawing', $ns)) {
    $svg += '<path fill="' + $geometry.GetAttribute('Brush') + '" d="' + $geometry.GetAttribute('Geometry') + '"/>'
}
$svg += '</svg>'
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'logo.svg'), [string[]]$svg, (New-Object Text.UTF8Encoding($false)))
Write-Host 'Created logo.svg, logo.png (512px), and logo.ico (16-256px).'
