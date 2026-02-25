# -----------------------------------------------------------------------------
# compile-dlls.ps1  -  Compila las DLL de SysOpt desde codigo fuente C#
# Ejecutar desde la carpeta  .\libs\  :  powershell -ExecutionPolicy Bypass -File compile-dlls.ps1
# -----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "  ====================================================" -ForegroundColor Cyan
Write-Host "    SysOpt - Compilacion de DLL externos              " -ForegroundColor Cyan
Write-Host "  ====================================================" -ForegroundColor Cyan
Write-Host ""

# -- Localizar csc.exe -------------------------------------------------------
$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) "csc.exe"
if (-not (Test-Path $csc)) {
    Write-Host "[ERROR] No se encontro csc.exe en $csc" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] csc.exe : $csc" -ForegroundColor Green

# -- Compilar cada DLL --------------------------------------------------------
$dlls = @(
    @{ Src = "SysOpt.ThemeEngine.cs";  Out = "SysOpt.ThemeEngine.dll"  },
    @{ Src = "SysOpt.Core.cs";         Out = "SysOpt.Core.dll"         }
)

foreach ($d in $dlls) {
    $src = Join-Path $here $d.Src
    $out = Join-Path $here $d.Out

    if (-not (Test-Path $src)) {
        Write-Host "[SKIP] Fuente no encontrado: $($d.Src)" -ForegroundColor Yellow
        continue
    }

    Write-Host ""
    Write-Host "[BUILD] $($d.Src) -> $($d.Out)" -ForegroundColor Cyan
    & $csc /target:library /optimize+ /nologo /out:$out $src 2>&1 | ForEach-Object {
        if ($_ -match "error") { Write-Host "  $_" -ForegroundColor Red }
        elseif ($_ -match "warning") { Write-Host "  $_" -ForegroundColor Yellow }
        else { Write-Host "  $_" -ForegroundColor Gray }
    }

    if (Test-Path $out) {
        $sz = (Get-Item $out).Length
        Write-Host "[OK] $($d.Out) compilado - $sz bytes" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] No se genero $($d.Out)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "[DONE] Compilacion finalizada." -ForegroundColor Green
Write-Host ""

# Nota: Las DLL ya existentes (MemoryHelper, DiskEngine) no se recompilan.
# Si necesitas recompilarlas, usa sus respectivos .cs de origen.
