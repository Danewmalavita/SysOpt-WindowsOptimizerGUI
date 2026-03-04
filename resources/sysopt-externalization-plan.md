# SysOpt 3.2.0 → 3.2.0 — Plan de Externalización Progresiva

**Fecha**: 2026-03-03  
**Objetivo**: Transformar SysOpt.ps1 de un monolito de 8575 líneas en un launcher ligero que carga DLLs y XAMLs.

---

## 📊 Estado Actual (v3.2.0)

| Componente | Líneas | % del total |
|------------|--------|-------------|
| Funciones (70 total) | 5,187 | 60% |
| → UI/Render (28 funcs) | 3,510 | 41% |
| → Data/Logic (8 funcs) | 241 | 3% |
| → Utilidades (34 funcs) | 1,436 | 17% |
| XAML inline (heredocs) | 1,247 | 14% |
| Init/Config/Handlers | ~2,141 | 25% |
| **Total** | **8,575** | **100%** |

### Clasificación de las 15 funciones más grandes

| Función | Líneas | XAML inline | Clasificación |
|---------|--------|-------------|---------------|
| Show-FolderScanner | 640 | 300 | **XAML-HEAVY** → Externalizar XAML + lógica a DLL |
| Start-DiskScan | 441 | 0 | UI-PURA → Thin wrapper en PS1 |
| Show-DiagnosticReport | 412 | 120 | **XAML-HEAVY** → Externalizar XAML + lógica a DLL |
| Show-TasksWindow | 397 | 283 | **XAML-HEAVY** → Externalizar XAML + lógica a DLL |
| Update-PerformanceTab | 272 | 0 | UI-PURA → Queda en PS1 |
| Apply-ThemeWithProgress | 234 | 0 | UI-PURA → Queda en PS1 |
| Show-StartupManager | 232 | 159 | **XAML-HEAVY** → Externalizar XAML + lógica a DLL |
| Start-Optimization | 230 | 0 | UI-PURA → Queda en PS1, lógica a DLL |
| Load-SnapshotList | 213 | 0 | HÍBRIDA → Lógica snapshot ya en DiskEngine.dll |
| Show-AboutWindow | 189 | 158 | **XAML-HEAVY** → Externalizar XAML |
| Get-SnapshotEntriesAsync | 164 | 0 | LÓGICA → Mover a DiskEngine.dll |
| Show-ExportProgressDialog | 159 | 0 | UI-PURA → Queda en PS1 |
| Show-OptionsWindow | 156 | 75 | **XAML-HEAVY** → Externalizar XAML |
| Show-ThemedDialog | 126 | 68 | **XAML-HEAVY** → Externalizar XAML |
| Show-ThemedInput | 108 | 51 | **XAML-HEAVY** → Externalizar XAML |

---

## 🗺️ Fases de Externalización

### FASE 2A: Externalizar XAML Inline → Archivos .xaml
**Riesgo**: ⬜ Bajo | **Impacto**: ~1,247 líneas eliminadas (14%)

Mover los 9 bloques XAML heredoc a archivos separados en `assets/xaml/`:

| Variable actual | Líneas | Archivo destino |
|----------------|--------|-----------------|
| `$fsXaml` (Show-FolderScanner) | 300 | `FolderScannerWindow.xaml` |
| `$twXaml` (Show-TasksWindow) | 283 | `TasksWindow.xaml` |
| `$startupXaml` (Show-StartupManager) | 159 | `StartupManagerWindow.xaml` |
| `$aboutXaml` (Show-AboutWindow) | 158 | `AboutWindow.xaml` |
| `$diagXaml` (Show-DiagnosticReport) | 120 | `DiagnosticWindow.xaml` |
| `$optXaml` (Show-OptionsWindow) | 75 | `OptionsWindow.xaml` |
| `$dlgXaml` (Show-ThemedDialog) | 68 | `ThemedDialog.xaml` |
| `$dlgXaml` (Show-ThemedInput) | 51 | `ThemedInput.xaml` |
| `$splashXaml` (ya parcial) | 33 | `SplashWindow.xaml` (ya existe) |

**Patrón de reemplazo:**
```powershell
# ANTES (300 líneas inline):
$fsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" ...>
  ...300 líneas...
</Window>
"@

# DESPUÉS (1 línea):
$fsXaml = [System.IO.File]::ReadAllText("$scriptDir\assets\xaml\FolderScannerWindow.xaml")
```

**Resultado estimado**: PS1 pasa de 8,575 → ~7,328 líneas (-14.5%)

---

### FASE 2B: Conectar código ya existente en DLLs (sin usar)
**Riesgo**: ⬜ Bajo | **Impacto**: ~200 líneas eliminadas + mejor rendimiento

`SysOpt.Core.dll` ya tiene clases completas que NO se usan desde PS1:

| Clase en Core.dll | Equivalente inline en PS1 | Acción |
|-------------------|--------------------------|--------|
| `SystemDataCollector` | Queries CIM inline en Update-SystemInfo, Update-PerformanceTab | Reemplazar llamadas inline |
| `LogEngine` | Write-Log inline | Reemplazar por `[SysOpt.Core.LogEngine]::Write()` |
| `ScanTokenManager` | `$script:ScanCtl211` (flag manual) | Consolidar en un solo mecanismo CTK |

**Ejemplo - SystemDataCollector:**
```powershell
# ANTES (inline en Update-SystemInfo, ~15 líneas):
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor
$ram = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
# ...más queries...

# DESPUÉS (1 línea):
$sysData = [SysOpt.Core.SystemDataCollector]::CollectAll()
```

---

### FASE 2C: Ampliar DLLs existentes
**Riesgo**: 🟨 Medio | **Impacto**: ~800-1200 líneas movidas

#### 2C.1 — Ampliar `SysOpt.Core.dll`
Mover a la DLL:
- **Funciones de formateo** (Format-Size, Format-Duration, etc.) → clase `Formatters`
- **Recolección de datos de rendimiento** → ampliar `SystemDataCollector`
- **Lógica de exportación** (generación HTML/CSV) → clase `ReportEngine`

#### 2C.2 — Ampliar `SysOpt.DiskEngine.dll`
Mover a la DLL:
- **Get-SnapshotEntriesAsync** (164 líneas) → `SnapshotEngine.GetEntriesAsync()`
- **Lógica de comparación de snapshots** → `SnapshotEngine.Compare()`
- **Lógica de escaneo de carpetas** (parte de Show-FolderScanner no-UI) → `FolderScanner`

#### 2C.3 — Ampliar `SysOpt.ThemeEngine.dll`
Mover a la DLL:
- **Apply-ComboBoxDarkTheme** (79 líneas) → `ThemeEngine.ApplyToComboBox()`
- **Apply-ButtonTheme** (56 líneas) → `ThemeEngine.ApplyToButton()`
- **Draw-SparkLine** (91 líneas) → `ThemeEngine.DrawSparkLine()` (o nueva DLL UI)

---

### FASE 2D: Nuevas DLLs especializadas
**Riesgo**: 🟧 Medio-Alto | **Impacto**: ~600-800 líneas movidas

#### `SysOpt.Optimizer.dll` (NUEVA)
Externalizar la lógica de optimización que NO toca UI:
- Limpieza de archivos temporales (Invoke-CleanTempPaths, 59 líneas)
- Operaciones de registro de Windows
- Gestión de servicios (habilitar/deshabilitar)
- Limpieza de DNS, caché, etc.

#### `SysOpt.StartupManager.dll` (NUEVA)
Externalizar la gestión de programas de inicio:
- Listar programas de inicio (registro + carpeta Startup + Task Scheduler)
- Habilitar/deshabilitar entradas
- Backup/restore de configuración

#### `SysOpt.Diagnostics.dll` (NUEVA)
Externalizar la recolección de datos de diagnóstico:
- Info de hardware
- Estado de drivers
- Checks de salud del sistema
- Generación de informe (datos, no UI)

---

### FASE 2E: PS1 como Launcher
**Riesgo**: 🟧 Medio-Alto | **Impacto**: Objetivo final

El PS1 quedaría con esta estructura (~2,000-2,500 líneas estimadas):

```
SysOpt.ps1 (Launcher)
├── [1] Init & Config (~150 líneas)
│   ├── Verificar admin/versión PS
│   ├── Cargar DLLs
│   └── Cargar configuración desde %AppData%
│
├── [2] Cargar UI (~100 líneas)
│   ├── Cargar XAML desde archivos
│   ├── Parsear y crear ventanas
│   └── Resolver FindName para controles
│
├── [3] Theme Engine (~100 líneas)
│   ├── Cargar tema
│   └── Aplicar colores (via ThemeEngine.dll)
│
├── [4] Event Wiring (~400 líneas)
│   ├── Add_Click handlers (thin wrappers → DLLs)
│   ├── Add_SelectionChanged
│   └── Timer events
│
├── [5] UI Update Functions (~800 líneas)
│   ├── Update-PerformanceTab (datos de DLL → UI)
│   ├── Refresh-DiskView (datos de DLL → UI)
│   ├── Apply-ThemeWithProgress
│   └── Otras funciones UI-puras
│
├── [6] Ventanas secundarias (~400 líneas)
│   ├── Show-* (cargan XAML + wiring mínimo)
│   └── Lógica delegada a DLLs
│
└── [7] Main Loop (~50 líneas)
    ├── Splash → MainWindow.ShowDialog()
    └── Cleanup
```

---

## 📅 Orden de ejecución recomendado

| Paso | Fase | Líneas eliminadas | PS1 resultante | Riesgo |
|------|------|--------------------|----------------|--------|
| 1 | **2A**: XAML → archivos | -1,247 | ~7,328 | ⬜ Bajo |
| 2 | **2B**: Conectar DLLs existentes | -200 | ~7,128 | ⬜ Bajo |
| 3 | **2C.1**: Ampliar Core.dll | -400 | ~6,728 | 🟨 Medio |
| 4 | **2C.2**: Ampliar DiskEngine.dll | -350 | ~6,378 | 🟨 Medio |
| 5 | **2C.3**: Ampliar ThemeEngine.dll | -226 | ~6,152 | 🟨 Medio |
| 6 | **2D**: Nuevas DLLs (Optimizer + StartupMgr + Diagnostics) | -800 | ~5,352 | 🟧 Medio-Alto |
| 7 | **2E**: Refactor PS1 como launcher | -2,800 | **~2,500** | 🟧 Medio-Alto |

**Reducción total estimada: de 8,575 → ~2,500 líneas (71% de reducción)**

---

## ⚠️ Consideraciones importantes

### PowerShell 5.1
- Las DLLs deben compilar contra **.NET Framework 4.x** (no .NET Core/5+)
- `Add-Type` funciona bien para cargar DLLs compiladas
- Los tipos WPF están en PresentationFramework.dll / PresentationCore.dll

### Compatibilidad XAML
- Los archivos .xaml externos se cargan con `[System.IO.File]::ReadAllText()` + `[System.Windows.Markup.XamlReader]::Parse()`
- Los placeholders de tema (`{ThemeBgColor}`, etc.) se reemplazan ANTES del parse — esto sigue funcionando igual con archivos externos

### Testing entre fases
- Cada fase debe ser testeada por separado antes de continuar
- El compilador `compile-dlls.ps1` debe actualizarse para incluir nuevas DLLs
- Mantener backup de la versión anterior en cada paso

### Limitaciones DLL ↔ PS1
- Las DLLs C# **no pueden acceder a variables de PS1** directamente
- Pattern recomendado: PS1 llama método estático de DLL pasando parámetros → DLL retorna datos → PS1 actualiza UI
- Los event handlers de WPF DEBEN quedarse en PS1 (capturan closures sobre controles)
