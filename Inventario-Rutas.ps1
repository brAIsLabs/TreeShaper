# TreeShaper - Copyright (C) 2026 brAIsLabs
# SPDX-License-Identifier: AGPL-3.0-or-later
# Licencia completa en el archivo LICENSE.

<#
.SYNOPSIS
    Inventaria una ruta local o de red (UNC o unidad mapeada) y genera un informe
    JSON con la estructura de carpetas/subcarpetas y ficheros (nombre, tamano y
    fecha de ultima modificacion), listo para cargar en Organizador-Rutas.html.

.DESCRIPTION
    - Recorre la ruta de forma recursiva.
    - No sigue junctions ni enlaces simbolicos: los registra como carpeta sin
      contenido y en meta.errores (evita bucles y duplicados). La ruta raiz
      indicada se escanea aunque sea un enlace.
    - Tamano de fichero en la unidad mas grande que aplique (KB / MB / GB).
    - Tolera rutas largas (>260 car.): reintenta con prefijo \\?\ y lo que no
      pueda leer lo registra en meta.errores (no aborta el recorrido).
    - Salida JSON UTF-8 sin BOM.

.PARAMETER Ruta
    Ruta a inventariar. Ej: \\SRV\Recurso\Carpeta  o  Z:\Carpeta

.PARAMETER Salida
    Carpeta donde se guarda el JSON (obligatorio). Si no existe, se crea.
    Una ruta relativa se resuelve desde la ubicacion actual.

.PARAMETER IncluirOcultos
    Si se indica, incluye ficheros y carpetas ocultos/de sistema.

.PARAMETER Profundidad
    Profundidad maxima de recorrido. -1 = sin limite (por defecto).

.EXAMPLE
    .\Inventario-Rutas.ps1 -Ruta "\\SRV-FS01\Grupo\Contabilidad" -Salida "C:\Inventarios"
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Ruta a inventariar (local, UNC o unidad mapeada)")]
    [string]$Ruta,

    [Parameter(Mandatory = $true, HelpMessage = "Carpeta donde se guarda el JSON")]
    [string]$Salida,

    [Parameter(Mandatory = $false)]
    [switch]$IncluirOcultos,

    [Parameter(Mandatory = $false)]
    [int]$Profundidad = -1
)

# Ruta absoluta una sola vez: New-Item (ubicacion de PowerShell) y WriteAllText
# (directorio actual de .NET) resolverian una ruta relativa contra sitios distintos.
$Salida = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Salida)

# --- Aprobacion (2/2): confirmacion S/N dentro del script ---------------------
Write-Host ""
Write-Host "=== Inventario de rutas de red ===" -ForegroundColor Cyan
Write-Host ("Ruta a inventariar : " + $Ruta)
Write-Host ("Carpeta de salida  : " + $Salida)
Write-Host ("Incluir ocultos    : " + [bool]$IncluirOcultos.IsPresent)
Write-Host ("Profundidad maxima : " + $(if ($Profundidad -lt 0) { "sin limite" } else { $Profundidad }))
Write-Host ("PowerShell         : " + $PSVersionTable.PSVersion.ToString())
Write-Host ""
$resp = Read-Host "Confirmas la ejecucion del inventario? (S/N)"
if ($resp -notmatch '^[SsYy]$') {
    Write-Host "Cancelado por el usuario." -ForegroundColor Yellow
    exit 0
}

# --- Estado global -----------------------------------------------------------
$script:errores       = New-Object System.Collections.Generic.List[string]
$script:totalArchivos = 0
$script:totalCarpetas = 0
$script:totalEnlaces  = 0

# --- Utilidades --------------------------------------------------------------
function Format-Tamano {
    param([double]$Bytes)
    $ic = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1073741824) { return ([math]::Round($Bytes / 1073741824, 2).ToString($ic) + " GB") }
    elseif ($Bytes -ge 1048576) { return ([math]::Round($Bytes / 1048576, 2).ToString($ic) + " MB") }
    else                        { return ([math]::Round($Bytes / 1024, 2).ToString($ic) + " KB") }
}

function ConvertTo-RutaLarga {
    param([string]$p)
    if ($p.StartsWith("\\?\")) { return $p }
    if ($p.StartsWith("\\"))   { return "\\?\UNC\" + $p.Substring(2) }
    return "\\?\" + $p
}

function Normalize-Path {
    param([string]$p)
    if ($p.StartsWith("\\?\UNC\")) { return "\\" + $p.Substring(8) }
    if ($p.StartsWith("\\?\"))     { return $p.Substring(4) }
    return $p
}

# --- Nucleo: construccion recursiva del arbol --------------------------------
function New-NodoCarpeta {
    param(
        [System.IO.DirectoryInfo]$Dir,
        [int]$Nivel
    )

    $script:totalCarpetas++
    if (($script:totalCarpetas % 200) -eq 0) {
        Write-Host ("  ... carpetas procesadas: " + $script:totalCarpetas)
    }

    $children     = New-Object System.Collections.Generic.List[object]
    $sumSize      = [long]0
    $countFiles   = 0
    $countFolders = 0

    $descender = ($Profundidad -lt 0) -or ($Nivel -lt $Profundidad)

    if ($descender) {
        $items = @()
        try {
            $items = Get-ChildItem -LiteralPath $Dir.FullName -Force:$IncluirOcultos.IsPresent -ErrorAction Stop
        }
        catch {
            # Reintento con prefijo de ruta larga
            try {
                $lp = ConvertTo-RutaLarga $Dir.FullName
                $items = Get-ChildItem -LiteralPath $lp -Force:$IncluirOcultos.IsPresent -ErrorAction Stop
            }
            catch {
                $script:errores.Add("No accesible: " + (Normalize-Path $Dir.FullName) + " :: " + $_.Exception.Message)
                $items = @()
            }
        }

        $subDirs = @($items | Where-Object { $_.PSIsContainer } | Sort-Object Name)
        $files   = @($items | Where-Object { -not $_.PSIsContainer } | Sort-Object Name)

        foreach ($sd in $subDirs) {
            # Junctions y enlaces simbolicos: se registran sin descender (bucles, duplicados,
            # salir de la raiz). Otros reparse points (DFS, nube, deduplicacion) se recorren.
            if ($sd.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $tipo = $null
                try { $tipo = $sd.LinkType } catch { $tipo = "Desconocido" }
                if ($tipo -in @("Junction", "SymbolicLink", "Desconocido")) {
                    $destino = "?"
                    try { $destino = (@($sd.Target) -join ", ") -replace '^\\\?\?\\', '' } catch { }
                    $script:totalCarpetas++
                    if ($tipo -eq "Desconocido") {
                        # Cuenta como ruta no leida: su contenido falta y debe saltar el AVISO final
                        $script:errores.Add("Enlace no identificado: " + (Normalize-Path $sd.FullName) + " -> " + $destino)
                    } else {
                        $script:totalEnlaces++
                        $script:errores.Add("Enlace no seguido (" + $tipo + "): " + (Normalize-Path $sd.FullName) + " -> " + $destino)
                    }
                    $children.Add([ordered]@{
                        name        = $sd.Name
                        type        = "folder"
                        path        = (Normalize-Path $sd.FullName)
                        size        = [long]0
                        sizeText    = (Format-Tamano 0)
                        modified    = $sd.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                        fileCount   = 0
                        folderCount = 0
                        linkType    = $tipo
                        children    = @()
                    })
                    $countFolders += 1
                    continue
                }
            }
            $nodo = New-NodoCarpeta -Dir $sd -Nivel ($Nivel + 1)
            $children.Add($nodo)
            $sumSize      += [long]$nodo.size
            $countFiles   += [int]$nodo.fileCount
            $countFolders += 1 + [int]$nodo.folderCount
        }

        foreach ($f in $files) {
            $script:totalArchivos++
            $countFiles++
            $sz = [long]$f.Length
            $sumSize += $sz
            $children.Add([ordered]@{
                name     = $f.Name
                type     = "file"
                path     = (Normalize-Path $f.FullName)
                size     = $sz
                sizeText = (Format-Tamano $sz)
                modified = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            })
        }
    }

    return [ordered]@{
        name        = $Dir.Name
        type        = "folder"
        path        = (Normalize-Path $Dir.FullName)
        size        = $sumSize
        sizeText    = (Format-Tamano $sumSize)
        modified    = $Dir.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        fileCount   = $countFiles
        folderCount = $countFolders
        children    = $children
    }
}

# --- Validacion de la ruta ---------------------------------------------------
if (-not (Test-Path -LiteralPath $Ruta)) {
    Write-Host ("ERROR: la ruta no existe o no es accesible: " + $Ruta) -ForegroundColor Red
    exit 1
}

$rootItem = $null
try {
    $rootItem = Get-Item -LiteralPath $Ruta -Force -ErrorAction Stop
}
catch {
    Write-Host ("ERROR: no se puede abrir la ruta: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

if (-not $rootItem.PSIsContainer) {
    Write-Host "ERROR: la ruta indicada es un fichero, no una carpeta." -ForegroundColor Red
    exit 1
}

# --- Recorrido ---------------------------------------------------------------
Write-Host ""
Write-Host "Escaneando (puede tardar en recursos grandes)..." -ForegroundColor Cyan
$cronometro = [System.Diagnostics.Stopwatch]::StartNew()

$arbol = New-NodoCarpeta -Dir $rootItem -Nivel 0

# El nombre de la raiz puede venir vacio si es la raiz de una unidad (Z:\)
if ([string]::IsNullOrWhiteSpace($arbol.name)) { $arbol.name = (Normalize-Path $rootItem.FullName) }

$cronometro.Stop()

# --- Construccion del informe ------------------------------------------------
$reporte = [ordered]@{
    meta = [ordered]@{
        schemaVersion = 1
        rootPath      = (Normalize-Path $rootItem.FullName)
        generatedAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        generatedBy   = $env:USERNAME
        machine       = $env:COMPUTERNAME
        psVersion     = $PSVersionTable.PSVersion.ToString()
        includeHidden = [bool]$IncluirOcultos.IsPresent
        maxDepth      = $Profundidad
        elapsedSec    = [math]::Round($cronometro.Elapsed.TotalSeconds, 1)
        totalFolders  = $script:totalCarpetas
        totalFiles    = $script:totalArchivos
        totalSize     = [long]$arbol.size
        totalSizeText = (Format-Tamano ([long]$arbol.size))
        errores       = $script:errores
    }
    tree = $arbol
}

$json = $reporte | ConvertTo-Json -Depth 100

# --- Escritura del fichero (UTF-8 sin BOM) -----------------------------------
if (-not (Test-Path -LiteralPath $Salida)) {
    New-Item -ItemType Directory -Path $Salida -Force | Out-Null
}

$nombreArchivo = "inventario_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json"
$rutaArchivo   = Join-Path $Salida $nombreArchivo
$utf8NoBom     = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($rutaArchivo, $json, $utf8NoBom)

# --- Resumen -----------------------------------------------------------------
Write-Host ""
Write-Host "=== Inventario completado ===" -ForegroundColor Green
Write-Host ("Carpetas         : " + $script:totalCarpetas)
Write-Host ("Ficheros         : " + $script:totalArchivos)
Write-Host ("Tamano total     : " + (Format-Tamano ([long]$arbol.size)))
Write-Host ("Tiempo           : " + [math]::Round($cronometro.Elapsed.TotalSeconds, 1) + " s")
Write-Host ("Rutas no leidas  : " + ($script:errores.Count - $script:totalEnlaces))
Write-Host ("Enlaces no seguidos: " + $script:totalEnlaces)
Write-Host ("Fichero JSON     : " + $rutaArchivo) -ForegroundColor Yellow
if (($script:errores.Count - $script:totalEnlaces) -gt 0) {
    Write-Host ""
    Write-Host "AVISO: hubo rutas no accesibles/demasiado largas. Revisa meta.errores en el JSON." -ForegroundColor Yellow
    Write-Host "       (Ejecutar con pwsh / PowerShell 7 reduce mucho estos casos.)" -ForegroundColor Yellow
}
