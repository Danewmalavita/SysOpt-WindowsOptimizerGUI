# SysOpt — Plan de Implementación: Fases 2D y 2E
**Fecha**: 2026-03-04  
**Estado de entrada**: Completadas fases 2A → 2C.3  
**PS1 actual**: 6,924 líneas  
**Objetivo**: PS1 final ~2,500 líneas (-64% adicional)

---

## 📊 Resumen de reducción esperada

| Paso | Fase | Líneas eliminadas | PS1 resultante | Riesgo |
|------|------|-------------------|----------------|--------|
| 6 | **2D.1** — SysOpt.Optimizer.dll | ~300 | ~6,624 | 🟧 Medio-Alto |
| 7 | **2D.2** — SysOpt.StartupManager.dll | ~50 | ~6,574 | 🟨 Medio |
| 8 | **2D.3** — SysOpt.Diagnostics.dll | ~800 | ~5,774 | 🟧 Medio-Alto |
| 9 | **2E** — Refactor PS1 como Launcher | ~3,200+ | **~2,500** | 🟧 Medio-Alto |

---

## FASE 2D — Nuevas DLLs especializadas

---

### PASO 6 — `SysOpt.Optimizer.dll`
**Riesgo**: 🟧 Medio-Alto | **Reducción estimada**: ~300 líneas del runspace worker

#### Contexto
`Start-Optimization` (386 líneas) delega el trabajo real a `$OptimizationScript`, un scriptblock que corre en un runspace separado. Ese scriptblock tiene toda la lógica sin UI: limpieza de temp, registro, DNS, caché de navegadores, SFC, DISM, etc. **Esa lógica pasa a C#.**

El PS1 conserva:
- Lectura de checkboxes y confirmación de usuario (`Show-ThemedDialog`)
- Construcción del `$options` hashtable
- Arranque del runspace y gestión del timer de polling (500 ms)
- Callbacks de progreso → actualización de `ProgressBar`, `ConsoleOutput`

#### Estructura C#

**Archivo**: `libs/csproj/SysOpt.Optimizer.cs`  
**csproj**: `libs/csproj/SysOpt.Optimizer.csproj` (target: .NET Framework 4.x)

```csharp
namespace SysOpt.Optimizer
{
    // DTO de opciones (serializable para pasar desde PS1)
    public class OptimizeOptions
    {
        public bool DryRun          { get; set; }
        public bool OptimizeDisks   { get; set; }
        public bool RecycleBin      { get; set; }
        public bool TempFiles       { get; set; }
        public bool UserTemp        { get; set; }
        public bool WUCache         { get; set; }
        public bool ClearMemory     { get; set; }
        public bool DNSCache        { get; set; }
        public bool BrowserCache    { get; set; }
        public bool BackupRegistry  { get; set; }
        public bool CleanRegistry   { get; set; }
        public bool SFC             { get; set; }
        public bool DISM            { get; set; }
        public bool EventLogs       { get; set; }
        public bool AutoRestart     { get; set; }
    }

    // Progreso individual de cada tarea
    public class OptimizeProgress
    {
        public string  TaskName    { get; set; }
        public int     Percent     { get; set; }    // 0-100 global
        public string  Message     { get; set; }
        public bool    IsError     { get; set; }
    }

    // Resultado de una tarea individual
    public class TaskResult
    {
        public string  TaskName    { get; set; }
        public bool    Success     { get; set; }
        public long    BytesFreed  { get; set; }
        public int     ItemsCount  { get; set; }
        public string  Detail      { get; set; }
        public string  Error       { get; set; }
    }

    // Resultado global de la sesión de optimización
    public class OptimizeResult
    {
        public bool               Cancelled    { get; set; }
        public bool               IsDryRun     { get; set; }
        public List<TaskResult>   Tasks        { get; set; }
        public long               TotalFreed   { get; set; }
        public DiagnosticReport   DiagReport   { get; set; }  // null si no es DryRun
        public string             Summary      { get; set; }
    }

    public static class OptimizerEngine
    {
        // Punto de entrada principal — llamado desde runspace PS1
        public static OptimizeResult Run(
            OptimizeOptions options,
            CancellationToken ct,
            IProgress<OptimizeProgress> progress);

        // Subtareas individuales — también llamables de forma independiente
        public static TaskResult CleanWindowsTemp(bool dryRun);
        public static TaskResult CleanUserTemp(bool dryRun);
        public static TaskResult EmptyRecycleBin(bool dryRun);
        public static TaskResult CleanWUCache(bool dryRun);
        public static TaskResult FlushDnsCache(bool dryRun);
        public static TaskResult CleanBrowserCache(bool dryRun);
        public static TaskResult BackupRegistry(string outputPath);
        public static TaskResult CleanRegistry(bool dryRun);
        public static TaskResult RunSFC(bool dryRun, CancellationToken ct,
                                        IProgress<OptimizeProgress> progress);
        public static TaskResult RunDISM(bool dryRun, CancellationToken ct,
                                         IProgress<OptimizeProgress> progress);
        public static TaskResult ClearEventLogs(bool dryRun);
        public static TaskResult OptimizeDisks(bool dryRun, CancellationToken ct,
                                               IProgress<OptimizeProgress> progress);
    }
}
```

#### Patrón de reemplazo en PS1

```powershell
# ANTES: $OptimizationScript = @" ...300 líneas de lógica en el runspace... "@
# El runspace ejecuta el scriptblock con toda la lógica C# duplicada en PS1.

# DESPUÉS: el runspace llama a la DLL con un scriptblock mínimo (~30 líneas):
$OptimizationScript = {
    param($window, $ConsoleOutput, $ProgressBar, $StatusText,
          $ProgressText, $TaskText, $options, $cancelToken)

    Add-Type -Path "$PSScriptRoot\libs\SysOpt.Optimizer.dll"

    $opts = [SysOpt.Optimizer.OptimizeOptions]::new()
    foreach ($key in $options.Keys) {
        $prop = $opts.GetType().GetProperty($key)
        if ($prop) { $prop.SetValue($opts, $options[$key]) }
    }

    $progress = [System.Progress[SysOpt.Optimizer.OptimizeProgress]]::new({
        param($p)
        $window.Dispatcher.Invoke([action]{
            $ProgressBar.Value   = $p.Percent
            $ProgressText.Text   = "$($p.Percent)%"
            $TaskText.Text       = $p.TaskName
            $ConsoleOutput.AppendText($p.Message + "`n")
            $ConsoleOutput.ScrollToEnd()
        })
    })

    $result = [SysOpt.Optimizer.OptimizerEngine]::Run($opts, $cancelToken, $progress)
    $DiagReportRef.Value = $result.DiagReport
}
```

#### Archivo `.csproj` nuevo

```xml
<!-- libs/csproj/SysOpt.Optimizer.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <AssemblyName>SysOpt.Optimizer</AssemblyName>
    <RootNamespace>SysOpt.Optimizer</RootNamespace>
    <Optimize>true</Optimize>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="SysOpt.Optimizer.cs" />
  </ItemGroup>
  <ItemGroup>
    <Reference Include="Microsoft.CSharp" />
  </ItemGroup>
</Project>
```

#### Actualizar `compile-dlls.ps1`
Añadir al script de compilación:
```powershell
Build-Dll "SysOpt.Optimizer" "SysOpt.Optimizer.cs"
```

---

### PASO 7 — `SysOpt.StartupManager.dll`
**Riesgo**: 🟨 Medio | **Reducción estimada**: ~45 líneas

#### Contexto
`Show-StartupManager` (79 líneas) ya tiene el XAML externalizado (2A). Lo que queda:
- Lectura de 3 rutas de registro (HKCU, HKLM, WOW6432Node)
- Construcción de la colección observable
- Lógica de aplicar cambios (`Remove-ItemProperty`)

Todo eso pasa a la DLL. El PS1 solo carga XAML, hace binding y llama a la DLL.

#### Estructura C#

**Archivo**: `libs/csproj/SysOpt.StartupManager.cs`

```csharp
namespace SysOpt.StartupManager
{
    public class StartupEntry
    {
        public bool   Enabled      { get; set; }
        public string Name         { get; set; }
        public string Command      get; set; }
        public string Source       { get; set; }    // "HKCU Run", "HKLM Run", etc.
        public string RegPath      { get; set; }
        public string OriginalName { get; set; }
        public string Type         { get; set; }    // "Registry" | "StartupFolder"
    }

    public class ApplyResult
    {
        public int  Disabled  { get; set; }
        public int  Errors    { get; set; }
        public List<string> ErrorDetails { get; set; }
    }

    public static class StartupEngine
    {
        // Lee entradas de registro + carpeta Startup del usuario
        public static List<StartupEntry> GetEntries();

        // Deshabilita (elimina del registro) una entrada
        public static bool DisableEntry(StartupEntry entry);

        // Rehabilita (restaura al registro) una entrada
        public static bool EnableEntry(StartupEntry entry);

        // Aplica todos los cambios pendientes (disabled en la colección)
        public static ApplyResult ApplyChanges(IEnumerable<StartupEntry> entries);

        // Exporta la lista actual como JSON para backup
        public static string ExportJson(IEnumerable<StartupEntry> entries);
    }
}
```

#### PS1 wrapper reducido (~35 líneas)

```powershell
function Show-StartupManager {
    $startupXaml = [XamlLoader]::Load($script:XamlFolder, "StartupManagerWindow")
    $startupXaml = $ExecutionContext.InvokeCommand.ExpandString($startupXaml)
    $sReader  = [System.Xml.XmlNodeReader]::new([xml]$startupXaml)
    $sWindow  = [Windows.Markup.XamlReader]::Load($sReader)
    $sGrid    = $sWindow.FindName("StartupGrid")
    $sStatus  = $sWindow.FindName("StartupStatus")
    $btnApply = $sWindow.FindName("btnApplyStartup")
    $btnClose = $sWindow.FindName("btnCloseStartup")
    $titleBar = $sWindow.FindName("titleBar")

    $script:_startupWin = $sWindow
    $titleBar.Add_MouseLeftButtonDown({ $script:_startupWin.DragMove() })

    # DLL hace el trabajo pesado
    $rawEntries    = [SysOpt.StartupManager.StartupEngine]::GetEntries()
    $startupTable  = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($e in $rawEntries) { $startupTable.Add($e) }

    $sGrid.ItemsSource = $startupTable
    $sStatus.Text      = "$($startupTable.Count) $(T 'startup_entries_found')"

    $btnApply.Add_Click({
        $result = [SysOpt.StartupManager.StartupEngine]::ApplyChanges($startupTable)
        $msg    = "$(T 'startup_applied'): $($result.Disabled) $(T 'startup_disabled')"
        if ($result.Errors -gt 0) { $msg += "`n$($result.Errors) $(T 'startup_errors')" }
        Show-ThemedDialog -Title (T 'startup_changes') -Message $msg -Type "success"
        Write-ConsoleMain "🚀 Startup Manager: $($result.Disabled) entradas desactivadas."
        $script:_startupWin.Close()
    })

    $btnClose.Add_Click({ $script:_startupWin.Close() })
    $sWindow.Owner = $window
    $sWindow.ShowDialog() | Out-Null
}
```

---

### PASO 8 — `SysOpt.Diagnostics.dll`
**Riesgo**: 🟧 Medio-Alto | **Reducción estimada**: ~800 líneas

#### Contexto
`Show-DiagnosticReport` tiene **951 líneas** y es la función más grande del PS1. Estructura actual:
- ~200 líneas: Helpers de UI inline (`Add-DiagSection`, `Add-DiagRow`, `Add-DiagGrid`) — recrean controles WPF en PowerShell
- ~650 líneas: Recolección de datos de CPU, RAM, discos, red, GPU, drivers, servicios, Windows Update, seguridad, temperatura
- ~100 líneas: Cálculo de score, exportación HTML, cierre de ventana

**Todo el bloque de recolección + score + exportación pasa a la DLL.**  
Los helpers UI (`Add-DiagRow`, etc.) también se mueven: la DLL devuelve DTOs, el PS1 los renderiza con funciones thin de ~5 líneas cada una.

#### Estructura C#

**Archivo**: `libs/csproj/SysOpt.Diagnostics.cs`

```csharp
namespace SysOpt.Diagnostics
{
    public enum DiagStatus { OK, WARN, CRIT, INFO }

    public class DiagEntry
    {
        public DiagStatus Status  { get; set; }
        public string     Label   { get; set; }
        public string     Detail  { get; set; }
        public string     Action  { get; set; }   // texto de acción sugerida (puede ser null)
    }

    public class DiagSection
    {
        public string          Title   { get; set; }
        public string          Icon    { get; set; }
        public List<DiagEntry> Entries { get; set; }
    }

    public class DiagnosticReport
    {
        public int                Score        { get; set; }  // 0-100
        public string             ScoreLabel   { get; set; }  // "Óptimo", "Advertencias", "Crítico"
        public string             Subtitle     { get; set; }
        public List<DiagSection>  Sections     { get; set; }
        public DateTime           Timestamp    { get; set; }

        // Datos raw para exportación
        public string             MachineName  { get; set; }
        public string             OSVersion    { get; set; }
    }

    public static class DiagnosticsEngine
    {
        // Recolecta todos los datos y devuelve el informe completo
        public static DiagnosticReport CollectAll();

        // Recolectores individuales (también llamables por separado)
        public static DiagSection CollectCpuInfo();
        public static DiagSection CollectMemoryInfo();
        public static DiagSection CollectDiskHealth();
        public static DiagSection CollectNetworkInfo();
        public static DiagSection CollectGpuInfo();
        public static DiagSection CollectSecurityInfo();
        public static DiagSection CollectWindowsUpdateInfo();
        public static DiagSection CollectDriversInfo();
        public static DiagSection CollectServicesInfo();

        // Calcula el score de 0-100 basado en el informe
        public static int CalculateScore(DiagnosticReport report);

        // Exportación
        public static string ExportToHtml(DiagnosticReport report, string templatePath);
        public static string ExportToText(DiagnosticReport report);
    }
}
```

#### PS1 wrapper reducido (~110 líneas)

```powershell
function Show-DiagnosticReport {
    param([hashtable]$Report)   # compatibilidad: si se pasa hashtable, se usa; si null, se recoge

    $diagXaml = [XamlLoader]::Load($script:XamlFolder, "DiagnosticWindow")
    $diagXaml = $ExecutionContext.InvokeCommand.ExpandString($diagXaml)
    $dReader  = [System.Xml.XmlNodeReader]::new([xml]$diagXaml)
    $dWindow  = [Windows.Markup.XamlReader]::Load($dReader)
    $dPanel   = $dWindow.FindName("DiagPanel")
    $dScore   = $dWindow.FindName("ScoreText")
    $dLabel   = $dWindow.FindName("ScoreLabel")
    $dSub     = $dWindow.FindName("DiagSubtitle")
    $btnExp   = $dWindow.FindName("btnExportDiag")
    $btnClose = $dWindow.FindName("btnCloseDiag")

    # Si el Report viene del DryRun como hashtable legacy, convertir a DiagnosticReport
    # En implementación nueva el runspace ya devuelve DiagnosticReport directamente
    $diagReport = if ($Report -is [SysOpt.Diagnostics.DiagnosticReport]) {
        $Report
    } else {
        [SysOpt.Diagnostics.DiagnosticsEngine]::CollectAll()
    }

    $dScore.Text = $diagReport.Score.ToString()
    $dLabel.Text = $diagReport.ScoreLabel
    $dSub.Text   = $diagReport.Subtitle

    # Renderizar secciones (UI pura en PS1, datos vienen de la DLL)
    foreach ($section in $diagReport.Sections) {
        Add-DiagSectionUI -Panel $dPanel -Window $dWindow `
                          -Title $section.Title -Icon $section.Icon
        foreach ($entry in $section.Entries) {
            Add-DiagRowUI -Panel $dPanel -Window $dWindow `
                          -Status $entry.Status -Label $entry.Label `
                          -Detail $entry.Detail -Action $entry.Action
        }
    }

    $btnExp.Add_Click({
        $html = [SysOpt.Diagnostics.DiagnosticsEngine]::ExportToHtml(
                    $diagReport, "$script:TemplatesFolder\diskreport.html")
        $outPath = "$script:OutputFolder\diag_$(Get-Date -f 'yyyyMMdd_HHmmss').html"
        [System.IO.File]::WriteAllText($outPath, $html)
        Start-Process $outPath
    })

    $btnClose.Add_Click({ $dWindow.Close() })
    $dWindow.Owner = $window
    $dWindow.ShowDialog() | Out-Null
}

# Helpers UI thin (~10 líneas cada uno, solo WPF binding)
function Add-DiagSectionUI { param($Panel, $Window, $Title, $Icon) ... }
function Add-DiagRowUI     { param($Panel, $Window, $Status, $Label, $Detail, $Action) ... }
```

---

## FASE 2E — PS1 como Launcher (`~2,500 líneas`)

Esta es la fase final y más compleja. Implica reorganizar el PS1 de forma estructural en 7 bloques claramente separados.

---

### Bloques del Launcher

#### [1] Init & Config (~150 líneas)
**Qué contiene ahora** (disperso por el PS1):
- Verificación de administrador (`Test-Administrator`) 
- Verificación de versión de PowerShell
- Carga de DLLs (`script:Load-SysOptDll`) 
- `$scriptDir`, `$script:XamlFolder`, paths globales
- Carga de configuración desde `%AppData%`

**Acciones 2E:**
- Consolidar todo al top del PS1
- `Test-Administrator` → reducir a ~10 líneas (eliminar output verboso, solo verifica + lanza UAC si necesario)
- Unificar todos los `$script:` path vars en un bloque `# === PATHS ===`

```powershell
# === [1] INIT & CONFIG ===
#region Init
Set-StrictMode -Version Latest
$script:Version    = "3.2.0"
$script:ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:XamlDir    = Join-Path $script:ScriptDir "assets\xaml"
$script:LangDir    = Join-Path $script:ScriptDir "assets\lang"
$script:ThemeDir   = Join-Path $script:ScriptDir "assets\themes"
$script:ImgDir     = Join-Path $script:ScriptDir "assets\img"
$script:TemplDir   = Join-Path $script:ScriptDir "assets\templates"
$script:LibsDir    = Join-Path $script:ScriptDir "libs"
$script:LogsDir    = Join-Path $script:ScriptDir "logs"
$script:OutputDir  = Join-Path $script:ScriptDir "output"
$script:SnapDir    = Join-Path $script:ScriptDir "snapshots"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}

[SysOpt.Core.LogEngine]::Initialize($script:LogsDir)
$script:Config = Load-Settings
#endregion
```

#### [2] Cargar DLLs (~30 líneas)
```powershell
#region LoadDLLs
$dllNames = @(
    "SysOpt.Core", "SysOpt.DiskEngine", "SysOpt.MemoryHelper",
    "SysOpt.ThemeEngine", "SysOpt.WseTrim",
    "SysOpt.Optimizer", "SysOpt.StartupManager", "SysOpt.Diagnostics"
)
foreach ($dll in $dllNames) {
    Add-Type -Path (Join-Path $script:LibsDir "$dll.dll") -ErrorAction Stop
}
#endregion
```

#### [3] Splash (~30 líneas)
- Mostrar `SplashWindow.xaml`
- Avanzar progress bar mientras cargan idioma + tema
- Ya está bastante limpio, solo simplificar

#### [4] Cargar Idioma y Tema (~80 líneas)
**Qué contiene ahora** (`Load-Language`, `Apply-LanguageToUI`, `Apply-ThemeWithProgress`, 450 líneas combinadas):  

- `Load-Language` (21 líneas) → queda en PS1, ya es thin
- `Apply-LanguageToUI` (165 líneas) → **reducir**: la traducción de ~120 controles sigue en PS1 (es un binding directo a UI), pero el parsing del `.lang` file pasa a `SysOpt.Core.LangEngine` (ya parcialmente en Core)
- `Apply-ThemeWithProgress` (212 líneas) → **reducir a ~60 líneas**: delegar a `[ThemeApplier]::ApplyAll()` ya existente en ThemeEngine.dll

#### [5] Cargar MainWindow XAML (~60 líneas)
```powershell
#region LoadMainWindow
$mainXaml = [XamlLoader]::Load($script:XamlDir, "MainWindow")
$mainXaml = $ExecutionContext.InvokeCommand.ExpandString($mainXaml)
$reader   = [System.Xml.XmlNodeReader]::new([xml]$mainXaml)
$window   = [Windows.Markup.XamlReader]::Load($reader)

# FindName para TODOS los controles — centralizado aquí
$btnStart         = $window.FindName("btnStart")
$btnDryRun        = $window.FindName("btnDryRun")
$btnCancel        = $window.FindName("btnCancel")
# ... resto de FindName ...
#endregion
```

#### [6] Event Wiring (~400 líneas)
Los handlers de eventos son el núcleo que **debe** quedarse en PS1. Pero se organizan en regiones claras:

```
#region EventWiring
  #region Optimization Events
    $btnStart.Add_Click({ Start-Optimization })
    $btnDryRun.Add_Click({ Start-Optimization -DryRunOverride $true })
    $btnCancel.Add_Click({ $script:CancelSource?.Cancel() })
  #endregion

  #region Disk Events
    $btnScan.Add_Click({ Start-DiskScan })
    $cmbDrives.Add_SelectionChanged({ Request-DiskViewRefresh })
  #endregion

  #region Theme/Settings Events
    $cmbTheme.Add_SelectionChanged({ Apply-ThemeWithProgress -ThemeName $cmbTheme.SelectedItem })
    $cmbLanguage.Add_SelectionChanged({ ... })
  #endregion

  #region Window Events
    $window.Add_Closing({ Save-Settings; [SysOpt.Core.LogEngine]::Close() })
    $titleBar.Add_MouseLeftButtonDown({ $window.DragMove() })
  #endregion
#endregion
```

#### [7] Funciones UI Residuales (~800 líneas)
Estas funciones quedan en PS1 porque son **UI-puras** (leen datos de DLLs y actualizan controles WPF):

| Función | Líneas estimadas | Nota |
|---------|-----------------|------|
| `Start-Optimization` | ~80 | Wrapper → SysOpt.Optimizer.dll |
| `Start-DiskScan` | ~100 | Wrapper → SysOpt.DiskEngine.dll |
| `Update-PerformanceTab` | ~80 | Datos de Core.dll → UI |
| `Refresh-DiskView` | ~50 | Datos de DiskEngine.dll → UI |
| `Apply-ThemeWithProgress` | ~60 | → ThemeEngine.dll |
| `Apply-LanguageToUI` | ~120 | Binding UI directo (imposible en DLL) |
| `Show-OptionsWindow` | ~50 | XAML ya externo, solo wiring |
| `Show-DiagnosticReport` | ~110 | Wrapper → SysOpt.Diagnostics.dll |
| `Show-StartupManager` | ~35 | Wrapper → SysOpt.StartupManager.dll |
| `Show-AboutWindow` | ~25 | Mínima, solo muestra info estática |
| `Show-ThemedDialog` | ~30 | Simplificado con helpers DLL |
| `Show-ThemedInput` | ~25 | Simplificado |
| `Show-TasksWindow` | ~35 | XAML externo, wiring |
| `Show-FolderScanner` | ~60 | Wrapper → DiskEngine.dll |
| `Add-DiagSectionUI` | ~15 | Helper UI thin |
| `Add-DiagRowUI` | ~20 | Helper UI thin |
| Helpers varios | ~50 | `Write-ConsoleMain`, `Get-SizeColor`, etc. |

#### [8] Main Loop (~50 líneas)
```powershell
#region Main
$splashWindow.Close()
[void]$window.ShowDialog()

# Cleanup
$script:CimSession?.Close()
[SysOpt.Core.LogEngine]::Close()
[GC]::Collect()
#endregion
```

---

## 📋 Orden de implementación recomendado

### Semana 1 — PASO 6: SysOpt.Optimizer.dll
1. Crear `libs/csproj/SysOpt.Optimizer.cs` con la estructura base
2. Extraer `$OptimizationScript` del PS1 → implementar en `OptimizerEngine.Run()`
3. Implementar subtarea por subtarea (empezar por las más simples: DNS, RecycleBin, Temp)
4. Dejar para el final: SFC y DISM (requieren `Process.Start` con captura de output)
5. Actualizar `compile-dlls.ps1` para incluir la nueva DLL
6. Reemplazar el scriptblock en PS1 por el wrapper de 30 líneas
7. ✅ Testing: ejecutar todas las tareas en modo DryRun primero

### Semana 2 — PASO 7: SysOpt.StartupManager.dll
1. Crear `libs/csproj/SysOpt.StartupManager.cs`
2. Implementar `GetEntries()` (leer registro + carpeta Startup)
3. Implementar `ApplyChanges()` (Remove-ItemProperty en C#)
4. Reemplazar `Show-StartupManager` por el wrapper de 35 líneas
5. ✅ Testing: verificar que las 3 rutas de registro se leen correctamente

### Semana 3 — PASO 8: SysOpt.Diagnostics.dll
1. Crear `libs/csproj/SysOpt.Diagnostics.cs`
2. Implementar DTOs (`DiagEntry`, `DiagSection`, `DiagnosticReport`)
3. Implementar recolectores uno a uno (CPU → RAM → Disk → Network → ...)
4. Implementar `CalculateScore()` (extraer la lógica del PS1 existente)
5. Implementar `ExportToHtml()` usando `diskreport.html` como plantilla
6. Reemplazar el bloque de 650 líneas en `Show-DiagnosticReport` por `CollectAll()`
7. ✅ Testing: comparar el informe generado por DLL vs el generado por PS1 actual

### Semana 4 — PASO 9: Refactor Launcher (2E)
> ⚠️ Esta fase tiene más riesgo. Hacer en sub-pasos, con backup del PS1 antes de cada sub-paso.

**Sub-paso 9a** — Reorganizar `#region` headers sin cambiar código (~2h)
- Añadir `#region [1] Init`, `#region [2] LoadDLLs`, etc.
- No mover código aún, solo estructurar
- Validar que el programa sigue funcionando

**Sub-paso 9b** — Consolidar Init & Paths (~4h)
- Unificar variables de path al top
- Simplificar `Test-Administrator`
- Consolidar `Load-SysOptDll`

**Sub-paso 9c** — Limpiar funciones UI residuales (~1 día)
- Reducir `Apply-LanguageToUI` delegando parsing a `SysOpt.Core.LangEngine`
- Reducir `Apply-ThemeWithProgress` a wrapper de `ThemeApplier`
- Eliminar funciones helper que ya tienen equivalente en DLLs

**Sub-paso 9d** — Consolidar Event Wiring en #region (~4h)
- Reunir todos los `Add_Click`, `Add_SelectionChanged` en el bloque [6]
- Asegurarse de que los handlers en lambdas todavía capturan las variables correctas (closures)

---

## ⚠️ Consideraciones específicas para estas fases

### Runspace y DLLs
Las DLLs que se usan dentro del runspace de optimización **deben cargarse dentro del runspace**:
```powershell
$OptimizationScript = {
    # CRÍTICO: cargar DLLs de nuevo dentro del runspace (no heredan el contexto del PS1 padre)
    Add-Type -Path "$using:LibsDir\SysOpt.Optimizer.dll"
    Add-Type -Path "$using:LibsDir\SysOpt.Core.dll"
    ...
}
```

### DiagnosticReport desde el Runspace
El `$DiagReportRef` (mecanismo de `[ref]` via `SessionStateProxy`) ya existe y funciona.  
La nueva DLL debe devolver un objeto `DiagnosticReport` que sea serializable entre runspaces.  
**Solución**: usar `[Serializable]` en todos los DTOs de Diagnostics.

### Proceso SFC/DISM en C#
```csharp
// En OptimizerEngine.cs
var psi = new ProcessStartInfo("sfc.exe", "/scannow") {
    UseShellExecute        = false,
    RedirectStandardOutput = true,
    CreateNoWindow         = true
};
using (var proc = Process.Start(psi)) {
    while (!proc.StandardOutput.EndOfStream && !ct.IsCancellationRequested) {
        var line = proc.StandardOutput.ReadLine();
        progress?.Report(new OptimizeProgress { Message = line, TaskName = "SFC" });
    }
    if (ct.IsCancellationRequested) proc.Kill();
    proc.WaitForExit();
    return new TaskResult { Success = proc.ExitCode == 0, TaskName = "SFC" };
}
```

### Compatibilidad .NET Framework 4.x
Las 3 nuevas DLLs deben compilar contra `.NET Framework 4.8` (igual que las existentes):
- Usar `List<T>` en lugar de colecciones .NET 5+
- `IProgress<T>` está disponible desde .NET 4.5 ✅
- `CancellationToken` está disponible desde .NET 4.0 ✅
- `Process.Start` + `RedirectStandardOutput` disponible en 4.x ✅

### Testing entre sub-pasos
- **Siempre** compilar y probar en DryRun antes de REAL
- Mantener el PS1 original como backup: `SysOpt.ps1.bak` en raíz
- El log en `logs/` es la principal herramienta de diagnóstico

---

## 📁 Archivos nuevos a crear

```
libs/
├── csproj/
│   ├── SysOpt.Optimizer.cs           ← NUEVO (Paso 6)
│   ├── SysOpt.Optimizer.csproj       ← NUEVO (Paso 6)
│   ├── SysOpt.StartupManager.cs      ← NUEVO (Paso 7)
│   ├── SysOpt.StartupManager.csproj  ← NUEVO (Paso 7)
│   ├── SysOpt.Diagnostics.cs         ← NUEVO (Paso 8)
│   └── SysOpt.Diagnostics.csproj     ← NUEVO (Paso 8)
├── SysOpt.Optimizer.dll              ← compilado (Paso 6)
├── SysOpt.StartupManager.dll         ← compilado (Paso 7)
├── SysOpt.Diagnostics.dll            ← compilado (Paso 8)
└── x86/
    ├── SysOpt.Optimizer.dll          ← compilado x86 (Paso 6)
    ├── SysOpt.StartupManager.dll     ← compilado x86 (Paso 7)
    └── SysOpt.Diagnostics.dll        ← compilado x86 (Paso 8)
```

---

*Generado automáticamente — SysOpt 3.2.0 → 3.2.0 Migration Plan*
