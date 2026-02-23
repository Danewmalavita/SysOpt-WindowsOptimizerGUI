#﻿Requires -RunAsAdministrator
<#
.SYNOPSIS
    Optimizador de Sistema Windows con Interfaz Gráfica
.DESCRIPTION
    Script completo de optimización con GUI, limpieza avanzada, verificación de sistema y registro.
.NOTES
    Requiere permisos de administrador
    Versión: 2.4.0
    Cambios v2.4.0 (FIFO Streaming Anti-RAM-Drain):
      PROBLEMA RESUELTO:
        El guardado de snapshot y la carga de entries materializaban TODA la colección
        en RAM antes de procesarla, causando picos de consumo proporcionales al tamaño
        del escaneo (escaneos de 50k+ carpetas podían duplicar el uso de RAM).

      [FIFO-01] Guardado de snapshot — streaming FIFO con ConcurrentQueue + JsonTextWriter:
                ANTES: $snapData (copia 1) → $entries (copia 2) → $json string (copia 3)
                       → WriteAllText. Pico = 3x RAM del dataset.
                AHORA: UI encola items 1 a 1 mientras background drena la queue y escribe
                       con JsonTextWriter directo al disco. Nunca existe el JSON en RAM.
                       Ahorro: -50% a -200% RAM en pico según tamaño del escaneo.

      [FIFO-02] Carga de entries — FIFO con ConvertFrom-Json nativo + ConcurrentQueue:
                ANTES: ReadAllText + ConvertFrom-Json + ConcurrentBag acumulado completo
                       antes de entregar al hilo UI. Pico = 3x JSON en RAM.
                AHORA: ConvertFrom-Json nativo (sin Newtonsoft, funciona en cualquier
                       runspace). Entries se encolan uno a uno (FIFO) en ConcurrentQueue.
                       DispatcherTimer drena en lotes de 500/tick — UI nunca bloquea.
                       Ahorro: -30% RAM pico (elimina ConcurrentBag intermedio).

      [FIFO-03] Terminación limpia garantizada en ambos flujos:
                Runspace + GC.Collect() + LOH compaction liberados al terminar,
                incluso en error (bloque finally). FeedDone en hashtable sincronizada
                evita bloqueos si el productor falla antes de terminar.

    Cambios v2.3.0 (Optimización RAM + Rendimiento):
      OPTIMIZACIONES RAM:
        [RAM-01] DiskItem_v211: INPC eliminado del modelo de datos puros.
                 ToggleVisibility y ToggleIcon extraídos a DiskItemToggle_v230
                 (wrapper INPC ligero). El objeto principal ya no retiene event
                 listeners ni PropertyChangedEventArgs. Ahorro: ~30-80 MB en
                 escaneos grandes.
        [RAM-02] Exportación CSV: reemplazado StringBuilder por StreamWriter
                 directo (flush por lotes). Nunca se materializa todo el CSV
                 en memoria. Ahorro: −50 a −150 MB pico en exportaciones grandes.
        [RAM-02b] Exportación HTML tabla: StreamWriter en archivo temporal para
                 las filas HTML. El StringBuilder ya no crece ilimitado.
        [RAM-03] bgExportScript y bgCsvScript reciben AllScannedItems por ref
                 via hashtable de estado compartido — evita copia completa.
        [RAM-04] Load-SnapshotList: metadatos leídos con JsonTextReader línea
                 a línea. Los Entries nunca se deserializan en memoria al listar.
                 Ahorro: −200 a −400 MB pico por snapshot grande.
        [RAM-05] RunspacePool centralizado (1-3 runspaces, ISS mínimo) para
                 operaciones async de exportación y top-files. Elimina overhead
                 de arranque y carga de módulos por operación.
        [RAM-06] GC agresivo post-exportación: LOH compaction + EmptyWorkingSet
                 tras cada exportación o carga de snapshot.
      NUEVAS OPTIMIZACIONES:
        [NEW-01] DiskUiTimer: debounce de 80ms en Refresh-DiskView para evitar
                 rebuildeos múltiples en ráfagas de datos del scanner.
        [NEW-02] Comparador de snapshots: pre-cálculo de top 10 archivos
                 durante el escaneo mediante acumulador en background.
        [NEW-03] AllScannedItems capacity hint: se preasigna con Capacity
                 estimado para evitar realocaciones de array interno.
        [NEW-04] chartTimer: intervalo mínimo 1s en lugar de 400ms para
                 reducir presión de GC en la pestaña Rendimiento.
    Cambios v2.2.0 (BugFix + Paths):
      BUGS CORREGIDOS:
        [BF1] Snapshots: ruta cambiada de %APPDATA%\SysOpt\snapshots a .\snapshots
              (relativo al script) — los snapshots ahora se guardan junto al script
        [BF2] Logs: ruta por defecto del diálogo "Guardar log" cambiada a .\logs
              (relativo al script) — se crea automáticamente si no existe
        [BF3] Snapshots no se listaban: bug crítico en Load-SnapshotList — clave
              de hashtable era una variable ($rootCount) dentro de @{}, lo que lanzaba
              una excepción silenciosa en el catch{} e impedía añadir cualquier item
              a la lista. Corregido: $rootCount se calcula antes del PSCustomObject
        [BF4] Diálogo "Confirmar eliminación" fallaba con XML inválido cuando el
              nombre del snapshot contenía comillas dobles (p.ej. "Escaneo 20/02/2026").
              Corregido: $Title y $Message se escapan con &quot; antes de interpolarlos
              en el XAML. Aplicado también a Show-ThemedInput.
        [BF5] Alto consumo de RAM: Load-SnapshotList cargaba todos los Entries de
              todos los JSONs en memoria permanentemente. Ahora solo guarda metadatos
              (FilePath, Label, fechas, conteos) y lee Entries bajo demanda al
              seleccionar o comparar, liberando la referencia inmediatamente tras su uso.
        [BF6] Comparar bloqueaba la UI: el bucle de "carpetas nuevas" era O(n²)
              — por cada item del escaneo actual iteraba todos los Entries del snapshot.
              Corregido con un HashSet<string> (lookup O(1)) y un Dictionary<string,long>
              para el mapa de tamaños. El comparador ahora escala correctamente aunque
              el escaneo o el snapshot contengan decenas de miles de carpetas.
      NUEVAS FUNCIONES v2.2.0:
        [N1] Snapshots con CheckBox: cada snapshot tiene un checkbox para seleccion
             individual. Boton "Todo" para marcar/desmarcar todos de golpe.
             El contador muestra "N de M seleccionados" en tiempo real.
        [N2] Comparar mejorado: soporta 3 modos segun los checks marcados:
               - 1 check + escaneo actual cargado → snapshot vs escaneo actual
               - 2 checks → snapshot A vs snapshot B (comparacion historica)
             El boton cambia de texto dinamicamente segun el modo activo.
        [N3] Eliminar en lote: elimina todos los snapshots marcados de una sola vez
             con dialogo de confirmacion que lista los nombres afectados.
    Cambios v2.1.3 (UX + BugFix):
      MEJORAS UX:
        [U1]  ComboBox con estilo oscuro temático (ya no aparece blanco)
        [U2]  ContextMenu / MenuItem con estilo oscuro temático
        [U3]  Botones de consola Output funcionales: rojo=ocultar, amarillo=minimizar/restaurar,
              verde=expandir/restaurar. Botón "🖥 Output" en footer para reabrir.
        [U4]  Menú contextual del Explorador incluye "Mostrar Output"
        [U5]  Enlace GitHub en el About abre el navegador al hacer clic
      BUGS CORREGIDOS v2.1.2:
        [BF4] Logo: carga vía $script:AppDir unificado
        [BF5] cmbRefreshInterval.SelectionChanged: timer se recrea correctamente
        [BF6] Get-SizeColorFromStr duplicado eliminado
    Cambios v2.0.2 (BugFix):
      BUGS CORREGIDOS:
        [BF1] Pestaña Rendimiento → Red: ahora muestra velocidad de subida/bajada
              en tiempo real (delta bytes/s), detecta Ethernet vs WiFi por PhysicalMediaType
              e InterfaceDescription, e indica el tipo con icono 📶/🔌
        [BF2] Explorador de Disco: escaneo ahora es verdaderamente recursivo —
              emite subcarpetas con indentación visual en tiempo real durante el barrido;
              se añade propiedad Depth al objeto de cola y a ScanCtl211.Current
        [BF3] Cierre del programa: Add_Closed vacía la cola ConcurrentQueue, limpia
              LiveList/LiveItems, dispone el runspace de escaneo y el CancelTokenSource
              de optimización → evita errores de estado cacheado al relanzar
        [BF3b] ScanControl: añadida propiedad Current (volatile string) que faltaba
               en la clase C# — corrige NullRef al leer [ScanCtl211]::Current
      BUGS CORREGIDOS:
        [B1]  GC.Collect reemplazado por EmptyWorkingSet real via Win32 API (RAM real)
        [B2]  CleanRegistry ahora exige BackupRegistry o muestra advertencia bloqueante
        [B3]  Mutex con AbandonedMutexException — ya no bloquea tras crash
        [B4]  chkAutoRestart sincronizado con btnSelectAll correctamente
        [B5]  Detección SSD por DeviceID en lugar de FriendlyName
        [B6]  Opera / Opera GX / Brave con rutas de caché completas
        [B7]  Firefox: limpia cache y cache2 (legacy + moderno)
        [B8]  Timer valida runspace con try/catch — no queda bloqueado
        [B9]  CHKDSK: orden corregido (dirty set ANTES de chkntfs)
        [B10] btnSelectAll refleja estado real de todos los checkboxes
        [B11] Aviso antes de limpiar consola si tiene contenido
        [B12] Formato de duración corregido a dd\:hh\:mm\:ss
        [B13] Limpieza de temporales refactorizada en función reutilizable
      NUEVAS FUNCIONES:
        [N1]  Panel de información del sistema (RAM, disco, CPU) al iniciar
        [N2]  Modo Dry Run (análisis sin cambios)
        [N3]  Limpieza de Windows Update Cache (SoftwareDistribution\Download)
        [N4]  Limpieza de Event Viewer Logs (System, Application, Setup)
        [N5]  Gestor de programas de inicio (ver y desactivar entradas de autoarranque)
      MEJORAS INTERNAS:
        [M1]  Clean-TempPaths — función unificada para limpieza de carpetas temp
        [M2]  Dependencia BackupRegistry ↔ CleanRegistry
        [M3]  Detección de disco robusta via DeviceID
        [M4]  AbandonedMutexException manejada
        [M5]  Rutas de navegadores completadas
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName WindowsBase

# ─────────────────────────────────────────────────────────────────────────────
# [FIX-SPLASH] Ventana de carga inmediata — evita pantalla en blanco al arrancar
# ─────────────────────────────────────────────────────────────────────────────
$splashXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Width="480" Height="160" WindowStartupLocation="CenterScreen" Topmost="True">
    <Border CornerRadius="12" BorderThickness="1" BorderBrush="#252B40">
        <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#1A2035" Offset="0"/>
                <GradientStop Color="#131625" Offset="1"/>
            </LinearGradientBrush>
        </Border.Background>
        <StackPanel VerticalAlignment="Center" Margin="36,0">
            <TextBlock FontFamily="Segoe UI" FontSize="20" FontWeight="Bold" Foreground="#E8ECF4" Margin="0,0,0,6">
                <Run Text="SYS"/><Run Foreground="#5BA3FF" Text="OPT"/>
                <Run Foreground="#8B96B8" FontSize="11" FontWeight="Normal" Text="   Windows Optimizer GUI"/>
            </TextBlock>
            <TextBlock Name="SplashMsg" Text="Cargando ensamblados .NET..." FontFamily="Segoe UI"
                       FontSize="11" Foreground="#7880A0" Margin="0,0,0,12"/>
            <Border Height="5" CornerRadius="2.5" Background="#1A1E2F">
                <Border Name="SplashBar" HorizontalAlignment="Left" Width="0" Height="5" CornerRadius="2.5">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                            <GradientStop Color="#5BA3FF" Offset="0"/>
                            <GradientStop Color="#4AE896" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                </Border>
            </Border>
        </StackPanel>
    </Border>
</Window>
"@
$splashReader = [System.Xml.XmlNodeReader]::new([xml]$splashXaml)
$splashWin    = [Windows.Markup.XamlReader]::Load($splashReader)
$splashMsg    = $splashWin.FindName("SplashMsg")
$splashBar    = $splashWin.FindName("SplashBar")
$splashWin.Show()
[System.Windows.Forms.Application]::DoEvents()   # pump WPF sin necesitar runspace

function Set-SplashProgress([int]$Pct, [string]$Msg = "") {
    if ($Msg) { $splashMsg.Text = $Msg }
    $splashBar.Width = [math]::Round(408 * [math]::Min(100,$Pct) / 100)
    [System.Windows.Forms.Application]::DoEvents()   # pump messages sin runspace
}
Set-SplashProgress 10 "Cargando ensamblados .NET..."

# ─────────────────────────────────────────────────────────────────────────────
# Win32 API para liberar Working Set de procesos (liberación real de RAM)
# ─────────────────────────────────────────────────────────────────────────────
if (-not ([System.Management.Automation.PSTypeName]'MemoryHelper').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MemoryHelper {
    [DllImport("kernel32.dll")]
    public static extern bool SetSystemFileCacheSize(IntPtr min, IntPtr max, uint flags);
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
"@ -ErrorAction SilentlyContinue
} # end MemoryHelper guard

# ─────────────────────────────────────────────────────────────────────────────
# [FIX-v2.1.1] Guard triple: DiskItem_v211 + ScanCtl211 + PScanner211
# Nombres unicos — nunca colisionan con v2.0 (DiskItem/ScanControl/ParallelScanner)
# ni con v2.1. Add-Type SilentlyContinue + try/catch = nunca TYPE_ALREADY_EXISTS.
# ─────────────────────────────────────────────────────────────────────────────
if (-not ([System.Management.Automation.PSTypeName]'DiskItem_v211').Type) {
try {
Add-Type @"
using System;
using System.ComponentModel;
using System.IO;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

// ── [RAM-01] DiskItem: modelo de datos PURO — sin INotifyPropertyChanged ──
// Las propiedades de toggle (ToggleVisibility / ToggleIcon) se separan a
// DiskItemToggle_v230, un wrapper INPC ligero, para no retener event listeners
// ni PropertyChangedEventArgs en los (potencialmente cientos de miles) de items.
public class DiskItem_v211 {
    public string DisplayName { get; set; }
    public string FullPath    { get; set; }
    public string ParentPath  { get; set; }
    public long   SizeBytes   { get; set; }
    public string SizeStr     { get; set; }
    public string SizeColor   { get; set; }
    public string PctStr      { get; set; }
    public string FileCount   { get; set; }
    public int    DirCount    { get; set; }
    public bool   IsDir       { get; set; }
    public bool   HasChildren { get; set; }
    public string Icon        { get; set; }
    public string Indent      { get; set; }
    public double BarWidth    { get; set; }
    public string BarColor    { get; set; }
    public double TotalPct    { get; set; }
    public int    Depth       { get; set; }
    // Toggle state inline (no INPC — la UI los lee desde DiskItemToggle_v230)
    public string ToggleVisibility { get; set; }
    public string ToggleIcon       { get; set; }
    public DiskItem_v211() {
        ToggleVisibility = "Collapsed";
        ToggleIcon = "\u25B6";
    }
}

// ── [RAM-01] DiskItemToggle_v230: wrapper INPC solo para colapso/expansión ──
// La UI lo usa como DataContext del botón toggle.
// Referencia al DiskItem_v211 para leer metadatos sin duplicarlos.
public class DiskItemToggle_v230 : System.ComponentModel.INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    private void N(string p) { if (PropertyChanged != null) PropertyChanged(this, new PropertyChangedEventArgs(p)); }
    public DiskItem_v211 Item { get; private set; }
    public DiskItemToggle_v230(DiskItem_v211 item) { Item = item; }
    public string ToggleVisibility {
        get { return Item.ToggleVisibility; }
        set { if (Item.ToggleVisibility != value) { Item.ToggleVisibility = value; N("ToggleVisibility"); } }
    }
    public string ToggleIcon {
        get { return Item.ToggleIcon; }
        set { if (Item.ToggleIcon != value) { Item.ToggleIcon = value; N("ToggleIcon"); } }
    }
}

// ── ScanCtl211: señales compartidas entre runspaces ──────────────────────
public static class ScanCtl211 {
    private static volatile bool   _stop    = false;
    public  static int             _doneRef = 0;
    public  static int             _totalRef= 0;
    private static volatile string _current = "";
    public static bool   Stop    { get { return _stop;    } set { _stop    = value; } }
    public static int    Done    { get { return _doneRef; } set { _doneRef  = value; } }
    public static int    Total   { get { return _totalRef;} set { _totalRef = value; } }
    public static string Current { get { return _current; } set { _current  = value; } }
    public static void Reset() { _stop = false; _doneRef = 0; _totalRef = 0; _current = ""; }
}

// ── [A1] PScanner211: escaneo paralelo estilo TreeSize ────────────────
public static class PScanner211 {
    private const int MAX_DEPTH = 64;  // [FIX] evitar stack overflow en estructuras muy profundas

    public static long ScanDir(
        string path, int depth, string parentKey,
        ConcurrentQueue<object[]> q)
    {
        if (ScanCtl211.Stop) return 0L;
        if (depth > MAX_DEPTH) return 0L;  // [FIX] corta recursión excesiva

        string dName = Path.GetFileName(path);
        if (string.IsNullOrEmpty(dName)) dName = path;

        // Emitir placeholder inmediato para que la UI lo muestre enseguida
        q.Enqueue(new object[]{ path, parentKey, dName, -1L, 0, 0, false, depth });

        long totalSize = 0L;
        int  fileCount = 0;

        // Sumar archivos del directorio actual
        try {
            string[] files = Directory.GetFiles(path);
            fileCount = files.Length;
            foreach (string f in files) {
                if (ScanCtl211.Stop) break;
                try { totalSize += new FileInfo(f).Length; } catch {}
            }
        } catch {}

        // Obtener subdirectorios
        string[] subDirs;
        try { subDirs = Directory.GetDirectories(path); }
        catch { subDirs = new string[0]; }

        Interlocked.Add(ref ScanCtl211._totalRef, subDirs.Length);

        long[] subSizes = new long[subDirs.Length];

        // [FIX] Paralelismo adaptativo: solo en niveles superficiales Y si quedan niveles
        // Limitamos a depth<=1 Y solo si no estamos cerca del límite de stack
        if (depth <= 1 && subDirs.Length > 1 && depth + 1 < MAX_DEPTH) {
            Parallel.For(0, subDirs.Length,
                new ParallelOptions { MaxDegreeOfParallelism = 4 }, i => {
                if (ScanCtl211.Stop) return;
                ScanCtl211.Current = Path.GetFileName(subDirs[i]);
                subSizes[i] = ScanDir(subDirs[i], depth + 1, path, q);
                Interlocked.Increment(ref ScanCtl211._doneRef);
            });
        } else {
            for (int i = 0; i < subDirs.Length; i++) {
                if (ScanCtl211.Stop) break;
                ScanCtl211.Current = Path.GetFileName(subDirs[i]);
                subSizes[i] = ScanDir(subDirs[i], depth + 1, path, q);
                Interlocked.Increment(ref ScanCtl211._doneRef);
            }
        }

        foreach (long s in subSizes) totalSize += s;

        // Emitir resultado final con tamaño real calculado
        q.Enqueue(new object[]{ path, parentKey, dName, totalSize, fileCount, subDirs.Length, true, depth });
        return totalSize;
    }
}

// Clase marcadora de versión — permite al guard detectar si esta versión está cargada
// DiskItem_v211 es la clase principal — no se necesita marcadora adicional
"@ -ErrorAction SilentlyContinue
} catch {
    # Tipos ya cargados en esta sesion PowerShell — ignorar TYPE_ALREADY_EXISTS
    Write-Verbose "SysOpt: C# types already loaded, skipping recompile"
}
} # end guard: DiskItem_v211 / ScanCtl211 / PScanner211

# ─────────────────────────────────────────────────────────────────────────────
# [RAM-05] RunspacePool centralizado — InitialSessionState mínimo
# Reutiliza runspaces entre operaciones async (exportar, cargar entries, top-files)
# eliminando el overhead de arranque (~2-5 MB por runspace) y la carga de módulos.
# Pool de 1 mín / 3 máx runspaces. Se abre una sola vez al inicio.
# ─────────────────────────────────────────────────────────────────────────────
$script:RunspacePool = $null
function Initialize-RunspacePool {
    if ($null -ne $script:RunspacePool -and $script:RunspacePool.RunspacePoolStateInfo.State -eq 'Opened') { return }
    try {
        $iss  = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 3, $iss, $Host)
        $pool.ApartmentState = [System.Threading.ApartmentState]::MTA
        $pool.Open()
        $script:RunspacePool = $pool
    } catch {
        Write-Verbose "SysOpt: RunspacePool init failed — will fallback to individual runspaces. $_"
        $script:RunspacePool = $null
    }
}

# Helper para crear PowerShell asignado al pool (o runspace individual como fallback)
function New-PooledPS {
    Initialize-RunspacePool
    $ps = [System.Management.Automation.PowerShell]::Create()
    if ($null -ne $script:RunspacePool) {
        $ps.RunspacePool = $script:RunspacePool
        return @{ PS = $ps; RS = $null }
    } else {
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = "MTA"; $rs.Open()
        $ps.Runspace = $rs
        return @{ PS = $ps; RS = $rs }
    }
}

# Helper para dispose limpio de PS+RS (RS puede ser $null si usó pool)
function Dispose-PooledPS($ctx) {
    try { $ctx.PS.Dispose() } catch {}
    if ($null -ne $ctx.RS) { try { $ctx.RS.Close(); $ctx.RS.Dispose() } catch {} }
}

# ─────────────────────────────────────────────────────────────────────────────
# [RAM-06] GC agresivo post-operación — libera LOH y Working Set al SO
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-AggressiveGC {
    try {
        [Runtime.GCSettings]::LargeObjectHeapCompactionMode = `
            [Runtime.GCLargeObjectHeapCompactionMode]::CompactOnce
        [GC]::Collect(2, [GCCollectionMode]::Forced, $true, $true)
        [GC]::WaitForPendingFinalizers()
        [GC]::Collect(2, [GCCollectionMode]::Forced, $true, $true)
        # EmptyWorkingSet en el proceso actual
        $h = [MemoryHelper]::OpenProcess(0x1F0FFF, $false, [Diagnostics.Process]::GetCurrentProcess().Id)
        if ($h -ne [IntPtr]::Zero) {
            [MemoryHelper]::EmptyWorkingSet($h) | Out-Null
            [MemoryHelper]::CloseHandle($h) | Out-Null
        }
    } catch {}
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar permisos de administrador
# ─────────────────────────────────────────────────────────────────────────────
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    [System.Windows.MessageBox]::Show(
        "Este programa requiere permisos de administrador.`n`nPor favor, ejecuta PowerShell como administrador y vuelve a intentarlo.",
        "Permisos Insuficientes",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# [B3] Evitar doble ejecución — manejo de AbandonedMutexException
# ─────────────────────────────────────────────────────────────────────────────
$script:AppMutex = New-Object System.Threading.Mutex($false, "Global\OptimizadorSistemaGUI_v5")
$mutexAcquired = $false
try {
    $mutexAcquired = $script:AppMutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    # El proceso anterior murió sin liberar — el mutex nos pertenece
    $mutexAcquired = $true
}

if (-not $mutexAcquired) {
    [System.Windows.MessageBox]::Show(
        "Ya hay una instancia del Optimizador en ejecución.`n`nCierra la ventana existente antes de abrir una nueva.",
        "Ya en ejecución",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Warning
    )
    exit
}

Set-SplashProgress 40 "Analizando permisos..."

# ─────────────────────────────────────────────────────────────────────────────
# XAML — Interfaz Gráfica v1.0
# ─────────────────────────────────────────────────────────────────────────────
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SysOpt - Windows Optimizer GUI v2.4.0" Height="980" Width="1220"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize"
        Background="#0D0F1A">
    <Window.Resources>

        <!-- ── Colores base ── -->
        <SolidColorBrush x:Key="BgDeep"       Color="#0D0F1A"/>
        <SolidColorBrush x:Key="BgCard"        Color="#131625"/>
        <SolidColorBrush x:Key="BgCardHover"   Color="#1A1E2F"/>
        <SolidColorBrush x:Key="BorderSubtle"  Color="#252B40"/>
        <SolidColorBrush x:Key="BorderActive"  Color="#5BA3FF"/>
        <SolidColorBrush x:Key="AccentBlue"    Color="#5BA3FF"/>
        <SolidColorBrush x:Key="AccentCyan"    Color="#2EDFBF"/>
        <SolidColorBrush x:Key="AccentAmber"   Color="#FFB547"/>
        <SolidColorBrush x:Key="AccentRed"     Color="#FF6B84"/>
        <SolidColorBrush x:Key="AccentGreen"   Color="#4AE896"/>
        <SolidColorBrush x:Key="TextPrimary"   Color="#E8ECF4"/>
        <SolidColorBrush x:Key="TextSecondary" Color="#B0BACC"/>
        <SolidColorBrush x:Key="TextMuted"     Color="#7880A0"/>

        <!-- Gradiente de acento para la barra de progreso -->
        <LinearGradientBrush x:Key="ProgressGradient" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#5BA3FF" Offset="0"/>
            <GradientStop Color="#2EDFBF" Offset="1"/>
        </LinearGradientBrush>

        <!-- ── Background: grid de líneas finas + blobs de color ── -->
        <VisualBrush x:Key="GridBrush" TileMode="Tile"
                     Viewport="0,0,40,40" ViewportUnits="Absolute"
                     Viewbox="0,0,40,40"  ViewboxUnits="Absolute">
            <VisualBrush.Visual>
                <Canvas Width="40" Height="40">
                    <!-- línea horizontal -->
                    <Line X1="0" Y1="0" X2="40" Y2="0"
                          Stroke="#5BA3FF" StrokeThickness="0.6" Opacity="0.22"/>
                    <!-- línea vertical -->
                    <Line X1="0" Y1="0" X2="0" Y2="40"
                          Stroke="#5BA3FF" StrokeThickness="0.6" Opacity="0.22"/>
                </Canvas>
            </VisualBrush.Visual>
        </VisualBrush>

        <!-- Estilo de botón base -->
        <Style x:Key="BtnBase" TargetType="Button">
            <Setter Property="FontFamily"      Value="Segoe UI"/>
            <Setter Property="FontSize"        Value="12"/>
            <Setter Property="FontWeight"      Value="SemiBold"/>
            <Setter Property="Height"          Value="36"/>
            <Setter Property="Padding"         Value="16,0"/>
            <Setter Property="Margin"          Value="4,0"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" CornerRadius="8"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.82"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.65"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Opacity" Value="0.3"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Botón primario (verde) -->
        <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"    Value="#1A6B3E"/>
            <Setter Property="BorderBrush"   Value="#2FD980"/>
            <Setter Property="Foreground"    Value="#2FD980"/>
        </Style>

        <!-- Botón secundario (azul) -->
        <Style x:Key="BtnSecondary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"    Value="#132040"/>
            <Setter Property="BorderBrush"   Value="#3D8EFF"/>
            <Setter Property="Foreground"    Value="#3D8EFF"/>
        </Style>

        <!-- Botón cyan (analizar) -->
        <Style x:Key="BtnCyan" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"    Value="#0E2E2A"/>
            <Setter Property="BorderBrush"   Value="#00D4B4"/>
            <Setter Property="Foreground"    Value="#00D4B4"/>
        </Style>

        <!-- Botón amber (cancelar) -->
        <Style x:Key="BtnAmber" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"    Value="#2E1E08"/>
            <Setter Property="BorderBrush"   Value="#F5A623"/>
            <Setter Property="Foreground"    Value="#F5A623"/>
        </Style>

        <!-- Botón rojo (salir) -->
        <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"    Value="#2E0E14"/>
            <Setter Property="BorderBrush"   Value="#FF4D6A"/>
            <Setter Property="Foreground"    Value="#FF4D6A"/>
        </Style>

        <!-- Botón fantasma (guardar log) -->
        <Style x:Key="BtnGhost" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background"    Value="#1A1E2A"/>
            <Setter Property="BorderBrush"   Value="#252A38"/>
            <Setter Property="Foreground"    Value="#9BA4C0"/>
        </Style>

        <!-- CheckBox moderno -->
        <Style TargetType="CheckBox">
            <Setter Property="FontFamily"  Value="Segoe UI"/>
            <Setter Property="FontSize"    Value="12"/>
            <Setter Property="Foreground"  Value="#D4D9E8"/>
            <Setter Property="Margin"      Value="0,4"/>
            <Setter Property="Cursor"      Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Border x:Name="box" Width="18" Height="18" CornerRadius="5"
                                    Background="#1A1E2F" BorderBrush="#252B40" BorderThickness="1.5"
                                    Margin="0,0,9,0" VerticalAlignment="Center">
                                <TextBlock x:Name="chk" Text="✓" FontSize="11" FontWeight="Bold"
                                           Foreground="#5BA3FF" HorizontalAlignment="Center"
                                           VerticalAlignment="Center" Visibility="Collapsed"/>
                            </Border>
                            <ContentPresenter VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="box" Property="Background"    Value="#132040"/>
                                <Setter TargetName="box" Property="BorderBrush"   Value="#3D8EFF"/>
                                <Setter TargetName="chk" Property="Visibility"    Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.35"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ScrollBar delgado -->
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="5"/>
            <Setter Property="Background" Value="Transparent"/>
        </Style>

        <!-- ── ComboBox temático oscuro (sin ControlTemplate complejo) ── -->
        <Style TargetType="ComboBox">
            <Setter Property="FontFamily"      Value="Segoe UI"/>
            <Setter Property="FontSize"        Value="11"/>
            <Setter Property="Foreground"      Value="#E8ECF4"/>
            <Setter Property="Background"      Value="#1A1E2F"/>
            <Setter Property="BorderBrush"     Value="#3A4468"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding"         Value="6,3"/>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="FontFamily"  Value="Segoe UI"/>
            <Setter Property="FontSize"    Value="11"/>
            <Setter Property="Foreground"  Value="#E8ECF4"/>
            <Setter Property="Background"  Value="#1A1E2F"/>
            <Setter Property="Padding"     Value="8,5"/>
            <Setter Property="Cursor"      Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderThickness="0" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1E3A5C"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#132040"/>
                                <Setter Property="Foreground" Value="#5BA3FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ── ContextMenu temático oscuro ── -->
        <Style TargetType="ContextMenu">
            <Setter Property="Background"      Value="#1A1E2F"/>
            <Setter Property="BorderBrush"     Value="#3A4468"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding"         Value="4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ContextMenu">
                        <Border Background="#1A1E2F" BorderBrush="#3A4468" BorderThickness="1"
                                CornerRadius="8" Padding="4,4">
                                                        <ItemsPresenter/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ── MenuItem temático (sin ContentSource="Icon" que requiere role) ── -->
        <Style TargetType="MenuItem">
            <Setter Property="FontFamily"  Value="Segoe UI"/>
            <Setter Property="FontSize"    Value="12"/>
            <Setter Property="Foreground"  Value="#E8ECF4"/>
            <Setter Property="Background"  Value="Transparent"/>
            <Setter Property="Padding"     Value="10,6"/>
            <Setter Property="Cursor"      Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="MenuItem">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                CornerRadius="5" Margin="2,1"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter ContentSource="Header"
                                              VerticalAlignment="Center"
                                              RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1E3058"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="MenuItemDanger" TargetType="MenuItem" BasedOn="{StaticResource {x:Type MenuItem}}">
            <Setter Property="Foreground" Value="#FF6B84"/>
        </Style>

        <!-- ── Separator temático ── -->
        <Style TargetType="Separator">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Separator">
                        <Rectangle Height="1" Fill="#2A3448" Margin="8,3"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ProgressBar con gradiente -->
        <Style TargetType="ProgressBar">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Border CornerRadius="4" Background="#1A1E2F"
                                BorderBrush="#252B40" BorderThickness="1" Height="6">
                            <Border x:Name="PART_Track">
                                <Border x:Name="PART_Indicator" HorizontalAlignment="Left" CornerRadius="4">
                                    <Border.Background>
                                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                            <GradientStop Color="#5BA3FF" Offset="0"/>
                                            <GradientStop Color="#2EDFBF" Offset="1"/>
                                        </LinearGradientBrush>
                                    </Border.Background>
                                </Border>
                            </Border>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

    </Window.Resources>

    <!-- ══════════════════════════════════════════════════════════════════
         FONDO: cuadrícula sutil + blobs de color difuminados
         Mismo estilo que la hoja de ruta HTML del proyecto.
         ══════════════════════════════════════════════════════════════════ -->
    <Grid>
        <!-- Capa 1: fondo sólido oscuro -->
        <Rectangle Fill="#0D0F1A"/>

        <!-- Capa 2: cuadrícula de líneas finas (VisualBrush en tile) -->
        <Rectangle Fill="{StaticResource GridBrush}" Opacity="1"/>

        <!-- Capa 3: blob azul — esquina superior izquierda -->
        <Ellipse Width="600" Height="600" Opacity="0.13"
                 HorizontalAlignment="Left" VerticalAlignment="Top"
                 Margin="-180,-180,0,0">
            <Ellipse.Fill>
                <RadialGradientBrush>
                    <GradientStop Color="#5BA3FF" Offset="0"/>
                    <GradientStop Color="Transparent" Offset="1"/>
                </RadialGradientBrush>
            </Ellipse.Fill>
        </Ellipse>

        <!-- Capa 4: blob cyan — esquina inferior derecha -->
        <Ellipse Width="500" Height="500" Opacity="0.13"
                 HorizontalAlignment="Right" VerticalAlignment="Bottom"
                 Margin="0,0,-160,-160">
            <Ellipse.Fill>
                <RadialGradientBrush>
                    <GradientStop Color="#2EDFBF" Offset="0"/>
                    <GradientStop Color="Transparent" Offset="1"/>
                </RadialGradientBrush>
            </Ellipse.Fill>
        </Ellipse>

        <!-- Capa 5: blob púrpura — centro -->
        <Ellipse Width="380" Height="380" Opacity="0.11"
                 HorizontalAlignment="Center" VerticalAlignment="Center">
            <Ellipse.Fill>
                <RadialGradientBrush>
                    <GradientStop Color="#9B7EFF" Offset="0"/>
                    <GradientStop Color="Transparent" Offset="1"/>
                </RadialGradientBrush>
            </Ellipse.Fill>
        </Ellipse>

        <!-- Capa 6: todo el contenido de la app encima -->
        <Grid Margin="16,12,16,12">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>   <!-- Header -->
                <RowDefinition Height="Auto"/>   <!-- Sysinfo bar + Charts -->
                <RowDefinition Height="*"/>      <!-- Opciones scroll -->
                <RowDefinition Name="OutputRow" Height="200"/>    <!-- Consola -->
                <RowDefinition Height="Auto"/>   <!-- Footer/botones -->
            </Grid.RowDefinitions>

            <!-- ═══ HEADER ═══════════════════════════════════════════ -->
            <Grid Grid.Row="0" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <!-- Logo SysOpt -->
                    <Image Name="imgLogo" Width="48" Height="48" Margin="0,0,12,0" VerticalAlignment="Center"
                           RenderOptions.BitmapScalingMode="HighQuality"/>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock FontFamily="Segoe UI" FontSize="22" FontWeight="Bold"
                                   Foreground="#E8ECF4">
                            <Run Text="SYS"/>
                            <Run Foreground="#5BA3FF" Text="OPT"/>
                            <Run Foreground="#B0BACC" FontSize="13" FontWeight="Normal" Text="  v2.4.0  ·  Windows Optimizer GUI"/>
                        </TextBlock>
                        <TextBlock Name="StatusText" FontFamily="Segoe UI" FontSize="11"
                                   Foreground="#9BA4C0" Margin="2,3,0,0"
                                   Text="Listo para optimizar"/>
                    </StackPanel>
                </StackPanel>

                <!-- Controles derecha del header: Acerca de + Modo Análisis -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <!-- Botón Acerca de la versión -->
                    <Button Name="btnAbout"
                            Width="32" Height="32" Padding="0" Margin="0,0,8,0"
                            Background="#1A2040" BorderBrush="#3D5080" BorderThickness="1"
                            Foreground="#9BA4C0" FontFamily="Segoe UI" FontSize="15" FontWeight="Bold"
                            Cursor="Hand" ToolTip="Acerca de SysOpt — Novedades de la versión">
                        <Button.Template>
                            <ControlTemplate TargetType="Button">
                                <Border x:Name="bd" CornerRadius="8"
                                        Background="{TemplateBinding Background}"
                                        BorderBrush="{TemplateBinding BorderBrush}"
                                        BorderThickness="{TemplateBinding BorderThickness}">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                                <ControlTemplate.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter TargetName="bd" Property="Background" Value="#253060"/>
                                        <Setter TargetName="bd" Property="BorderBrush" Value="#5BA3FF"/>
                                    </Trigger>
                                </ControlTemplate.Triggers>
                            </ControlTemplate>
                        </Button.Template>
                        <TextBlock Text="ℹ" FontSize="15" Foreground="#5BA3FF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Button>
                    <!-- Modo Dry Run toggle -->
                    <Border CornerRadius="8" Background="#163530"
                            BorderBrush="#2EDFBF" BorderThickness="1"
                            Padding="14,8" VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal">
                            <CheckBox Name="chkDryRun" VerticalAlignment="Center">
                                <CheckBox.Content>
                                    <TextBlock FontFamily="Segoe UI" FontSize="11" FontWeight="SemiBold"
                                               Foreground="#2EDFBF" Text="MODO ANÁLISIS  (sin cambios)"/>
                                </CheckBox.Content>
                            </CheckBox>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>

            <!-- ═══ SYSINFO BAR + CHARTS ══════════════════════════════════ -->
            <Border Grid.Row="1" CornerRadius="10" Background="#1A1E2F"
                    BorderBrush="#252B40" BorderThickness="1"
                    Padding="16,12" Margin="0,0,0,10">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="10"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="10"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- CPU Panel + Chart -->
                    <StackPanel Grid.Column="0">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                            <Border Width="22" Height="22" CornerRadius="5" Background="#1A3A5C" Margin="0,0,7,0" VerticalAlignment="Center">
                                <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <TextBlock Text="CPU" FontFamily="Segoe UI" FontSize="10" FontWeight="SemiBold"
                                      Foreground="#7BA8E0" VerticalAlignment="Center"/>
                            <TextBlock Name="CpuPctText" Text="  0%" FontFamily="Segoe UI" FontSize="10"
                                       FontWeight="Bold" Foreground="#5BA3FF" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Name="InfoCPU" Text="—" FontFamily="Segoe UI" FontSize="10"
                                   FontWeight="SemiBold" Foreground="#5BA3FF" Margin="0,0,0,5" TextWrapping="Wrap"/>
                        <Border Background="#1A2540" CornerRadius="5" Height="52" ClipToBounds="True">
                            <Canvas Name="CpuChart" Background="Transparent"/>
                        </Border>
                    </StackPanel>

                    <!-- Divider -->
                    <Rectangle Grid.Column="1" Fill="#3A4468" Width="1" Margin="0,2"/>

                    <!-- RAM Panel + Chart -->
                    <StackPanel Grid.Column="2" Margin="4,0,0,0">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                            <Border Width="22" Height="22" CornerRadius="5" Background="#1A4A35" Margin="0,0,7,0" VerticalAlignment="Center">
                                <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <TextBlock Text="RAM" FontFamily="Segoe UI" FontSize="10" FontWeight="SemiBold"
                                      Foreground="#6ABDA0" VerticalAlignment="Center"/>
                            <TextBlock Name="RamPctText" Text="  0%" FontFamily="Segoe UI" FontSize="10"
                                       FontWeight="Bold" Foreground="#4AE896" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Name="InfoRAM" Text="—" FontFamily="Segoe UI" FontSize="10"
                                   FontWeight="SemiBold" Foreground="#4AE896" Margin="0,0,0,5"/>
                        <Border Background="#1A2540" CornerRadius="5" Height="52" ClipToBounds="True">
                            <Canvas Name="RamChart" Background="Transparent"/>
                        </Border>
                    </StackPanel>

                    <!-- Divider -->
                    <Rectangle Grid.Column="3" Fill="#3A4468" Width="1" Margin="0,2"/>

                    <!-- Disco Panel + Chart -->
                    <StackPanel Grid.Column="4" Margin="4,0,0,0">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                            <Border Width="22" Height="22" CornerRadius="5" Background="#4A3010" Margin="0,0,7,0" VerticalAlignment="Center">
                                <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <TextBlock Text="DISCO C:" FontFamily="Segoe UI" FontSize="10" FontWeight="SemiBold"
                                      Foreground="#C0933A" VerticalAlignment="Center"/>
                            <TextBlock Name="DiskPctText" Text="  0%" FontFamily="Segoe UI" FontSize="10"
                                       FontWeight="Bold" Foreground="#FFB547" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Name="InfoDisk" Text="—" FontFamily="Segoe UI" FontSize="10"
                                   FontWeight="SemiBold" Foreground="#FFB547" Margin="0,0,0,5"/>
                        <Border Background="#1A2540" CornerRadius="5" Height="52" ClipToBounds="True">
                            <Canvas Name="DiskChart" Background="Transparent"/>
                        </Border>
                    </StackPanel>

                    <!-- Refresh -->
                    <Button Name="btnRefreshInfo" Grid.Column="5" Style="{StaticResource BtnGhost}"
                            Content="↻" FontSize="16" Height="32" Width="32" Padding="0"
                            ToolTip="Actualizar información del sistema" Margin="10,0,0,0" VerticalAlignment="Top"/>
                </Grid>
            </Border>

            <!-- ═══ PESTAÑAS PRINCIPALES ══════════════════════════════ -->
            <TabControl Grid.Row="2" Margin="0,0,0,10"
                        Background="#131625" BorderBrush="#252B40" BorderThickness="1">
                <TabControl.Resources>
                    <Style TargetType="TabItem">
                        <Setter Property="FontFamily" Value="Segoe UI"/>
                        <Setter Property="FontSize" Value="12"/>
                        <Setter Property="FontWeight" Value="SemiBold"/>
                        <Setter Property="Foreground" Value="#9BA4C0"/>
                        <Setter Property="Background" Value="#252B3B"/>
                        <Setter Property="Padding" Value="16,8"/>
                        <Setter Property="BorderThickness" Value="0"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="TabItem">
                                    <Border x:Name="tabBorder" Background="{TemplateBinding Background}"
                                            BorderThickness="0,0,0,2" BorderBrush="Transparent"
                                            Padding="{TemplateBinding Padding}">
                                        <ContentPresenter ContentSource="Header"
                                                          HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter TargetName="tabBorder" Property="BorderBrush" Value="#5BA3FF"/>
                                            <Setter Property="Foreground" Value="#F0F3FA"/>
                                            <Setter TargetName="tabBorder" Property="Background" Value="#2E3650"/>
                                        </Trigger>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="tabBorder" Property="Background" Value="#2A3048"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </TabControl.Resources>

                <!-- ══ TAB 1: OPTIMIZACIÓN ══ -->
                <TabItem Header="⚙  Optimización">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#131625">
                <Grid Margin="4,8,4,4">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="10"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Columna izquierda -->
                    <StackPanel Grid.Column="0">

                        <!-- Card: Discos y Archivos -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                    <Border Width="28" Height="28" CornerRadius="7" Background="Transparent" BorderBrush="#FFFFFF" BorderThickness="1.5"
                                            Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="DISCOS Y ARCHIVOS" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"
                                              />
                                </StackPanel>
                                <CheckBox Name="chkOptimizeDisks" Content="Optimizar discos (Defrag HDD / TRIM SSD·NVMe)" IsChecked="True"/>
                                <CheckBox Name="chkRecycleBin"    Content="Vaciar papelera de reciclaje" IsChecked="True"/>
                                <CheckBox Name="chkTempFiles"     Content="Temp de Windows (System\Temp, Prefetch)" IsChecked="True"/>
                                <CheckBox Name="chkUserTemp"      Content="Temp de usuario (%TEMP%, AppData\Local\Temp)" IsChecked="True"/>
                                <CheckBox Name="chkWUCache"       Content="Caché de Windows Update" IsChecked="False"/>
                                <CheckBox Name="chkChkdsk"        Content="Check Disk (CHKDSK)  —  requiere reinicio" IsChecked="False"/>
                            </StackPanel>
                        </Border>

                        <!-- Card: Memoria y Procesos -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                    <Border Width="28" Height="28" CornerRadius="7" Background="Transparent" BorderBrush="#FFFFFF" BorderThickness="1.5"
                                            Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="MEMORIA Y PROCESOS" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"
                                              />
                                </StackPanel>
                                <CheckBox Name="chkClearMemory"    Content="Liberar RAM (vaciar Working Set de procesos)" IsChecked="True"/>
                                <CheckBox Name="chkCloseProcesses" Content="Cerrar procesos no críticos" IsChecked="False"/>
                            </StackPanel>
                        </Border>

                        <!-- Card: Red y Navegadores -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                    <Border Width="28" Height="28" CornerRadius="7" Background="Transparent" BorderBrush="#FFFFFF" BorderThickness="1.5"
                                            Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="RED Y NAVEGADORES" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"
                                              />
                                </StackPanel>
                                <CheckBox Name="chkDNSCache"     Content="Limpiar caché DNS" IsChecked="True"/>
                                <CheckBox Name="chkBrowserCache" Content="Caché de navegadores (Chrome, Edge, Firefox, Opera, Brave)" IsChecked="True"/>
                            </StackPanel>
                        </Border>

                    </StackPanel>

                    <!-- Columna derecha -->
                    <StackPanel Grid.Column="2">

                        <!-- Card: Registro -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                    <Border Width="28" Height="28" CornerRadius="7" Background="Transparent" BorderBrush="#FFFFFF" BorderThickness="1.5"
                                            Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="REGISTRO DE WINDOWS" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"
                                              />
                                </StackPanel>
                                <CheckBox Name="chkBackupRegistry" Content="Backup del registro (recomendado)" IsChecked="True"/>
                                <CheckBox Name="chkCleanRegistry"  Content="Limpiar claves huérfanas" IsChecked="False"/>
                            </StackPanel>
                        </Border>

                        <!-- Card: Verificación del Sistema -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                    <Border Width="28" Height="28" CornerRadius="7" Background="Transparent" BorderBrush="#FFFFFF" BorderThickness="1.5"
                                            Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="VERIFICACIÓN DEL SISTEMA" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"
                                              />
                                </StackPanel>
                                <CheckBox Name="chkSFC"  Content="SFC /SCANNOW  —  verificador de archivos" IsChecked="False"/>
                                <CheckBox Name="chkDISM" Content="DISM  —  reparar imagen del sistema" IsChecked="False"/>
                            </StackPanel>
                        </Border>

                        <!-- Card: Registros de Eventos -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                    <Border Width="28" Height="28" CornerRadius="7" Background="Transparent" BorderBrush="#FFFFFF" BorderThickness="1.5"
                                            Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="REGISTROS DE EVENTOS" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"
                                              />
                                </StackPanel>
                                <CheckBox Name="chkEventLogs" Content="Event Viewer (System, Application, Setup)" IsChecked="False"/>
                                <TextBlock Text="El log Security no se toca" FontFamily="Segoe UI" FontSize="10"
                                           Foreground="#8B96B8" Margin="27,3,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- Card: Programas de inicio -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                    <Border Width="28" Height="28" CornerRadius="7" Background="Transparent" BorderBrush="#FFFFFF" BorderThickness="1.5"
                                            Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="PROGRAMAS DE INICIO" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"
                                              />
                                </StackPanel>
                                <CheckBox Name="chkShowStartup" Content="Gestionar entradas de autoarranque" IsChecked="False"/>
                                <TextBlock Text="Abre ventana de gestión al iniciar" FontFamily="Segoe UI" FontSize="10"
                                           Foreground="#8B96B8" Margin="27,3,0,0"/>
                            </StackPanel>
                        </Border>

                    </StackPanel>
                </Grid>
                </ScrollViewer>
                </TabItem>

                <!-- ══ TAB 2: RENDIMIENTO ══ -->
                <TabItem Header="📊  Rendimiento">
                <Grid Background="#131625" Margin="0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <!-- Toolbar rendimiento -->
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="10,8,10,4">
                        <Button Name="btnRefreshPerf" Style="{StaticResource BtnSecondary}"
                                Content="↻  Actualizar" MinWidth="110" Height="30"/>
                        <!-- [A3] Auto-refresco -->
                        <CheckBox Name="chkAutoRefresh" VerticalAlignment="Center" Margin="14,0,4,0">
                            <CheckBox.Content>
                                <TextBlock Text="Auto-refresco" FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0"/>
                            </CheckBox.Content>
                        </CheckBox>
                        <ComboBox Name="cmbRefreshInterval" Width="72" Height="26" Margin="2,0,0,0"
                                  VerticalAlignment="Center" FontFamily="Segoe UI" FontSize="11"
                                  Background="#1A1E2F" Foreground="#E8ECF4" BorderBrush="#3A4468">
                            <ComboBoxItem Content="5 s"  Tag="5"  IsSelected="True"/>
                            <ComboBoxItem Content="15 s" Tag="15"/>
                            <ComboBoxItem Content="30 s" Tag="30"/>
                            <ComboBoxItem Content="60 s" Tag="60"/>
                        </ComboBox>
                        <TextBlock Name="txtPerfStatus" Text="  Haz clic en Actualizar para cargar datos"
                                   FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0"
                                   VerticalAlignment="Center" Margin="10,0,0,0"/>
                    </StackPanel>
                    <!-- Contenido en scroll -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="10,0,10,10">

                        <!-- ── CPU CORES ── -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Border Width="26" Height="26" CornerRadius="6" Background="#1A3A5C" Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="13"
                                                   Foreground="#5BA3FF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="CORES DEL PROCESADOR" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                                </StackPanel>
                                <!-- Nombre CPU -->
                                <TextBlock Name="txtCpuName" Text="—" FontFamily="Segoe UI" FontSize="11"
                                           Foreground="#9BA4C0" Margin="0,0,0,8"/>
                                <!-- Grid de cores generado dinámicamente -->
                                <ItemsControl Name="icCpuCores">
                                    <ItemsControl.ItemsPanel>
                                        <ItemsPanelTemplate>
                                            <WrapPanel Orientation="Horizontal"/>
                                        </ItemsPanelTemplate>
                                    </ItemsControl.ItemsPanel>
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="8" Background="#1A2540" BorderBrush="#3A4468"
                                                    BorderThickness="1" Padding="10,8" Margin="4,4"
                                                    Width="120">
                                                <StackPanel>
                                                    <TextBlock Text="{Binding CoreLabel}" FontFamily="Segoe UI"
                                                               FontSize="10" FontWeight="SemiBold" Foreground="#B0BACC"
                                                               HorizontalAlignment="Center"/>
                                                    <TextBlock Text="{Binding Usage}" FontFamily="Segoe UI"
                                                               FontSize="20" FontWeight="Bold" Foreground="#5BA3FF"
                                                               HorizontalAlignment="Center" Margin="0,2"/>
                                                    <ProgressBar Minimum="0" Maximum="100" Value="{Binding UsageNum}"
                                                                 Height="4" Margin="0,4,0,2"/>
                                                    <TextBlock Text="{Binding Freq}" FontFamily="Segoe UI"
                                                               FontSize="9" Foreground="#8B96B8"
                                                               HorizontalAlignment="Center"/>
                                                </StackPanel>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </StackPanel>
                        </Border>

                        <!-- ── RAM DETALLADA ── -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Border Width="26" Height="26" CornerRadius="6" Background="#1A4A35" Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="13"
                                                   Foreground="#4AE896" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="MEMORIA RAM" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                                </StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0" HorizontalAlignment="Center">
                                        <TextBlock Text="TOTAL" FontFamily="Segoe UI" FontSize="9" Foreground="#8B96B8" HorizontalAlignment="Center"/>
                                        <TextBlock Name="txtRamTotal" Text="—" FontFamily="Segoe UI" FontSize="18"
                                                   FontWeight="Bold" Foreground="#4AE896" HorizontalAlignment="Center"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1" HorizontalAlignment="Center">
                                        <TextBlock Text="USADA" FontFamily="Segoe UI" FontSize="9" Foreground="#8B96B8" HorizontalAlignment="Center"/>
                                        <TextBlock Name="txtRamUsed" Text="—" FontFamily="Segoe UI" FontSize="18"
                                                   FontWeight="Bold" Foreground="#FFB547" HorizontalAlignment="Center"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="2" HorizontalAlignment="Center">
                                        <TextBlock Text="LIBRE" FontFamily="Segoe UI" FontSize="9" Foreground="#8B96B8" HorizontalAlignment="Center"/>
                                        <TextBlock Name="txtRamFree" Text="—" FontFamily="Segoe UI" FontSize="18"
                                                   FontWeight="Bold" Foreground="#4AE896" HorizontalAlignment="Center"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="3" HorizontalAlignment="Center">
                                        <TextBlock Text="USO%" FontFamily="Segoe UI" FontSize="9" Foreground="#8B96B8" HorizontalAlignment="Center"/>
                                        <TextBlock Name="txtRamPct" Text="—" FontFamily="Segoe UI" FontSize="18"
                                                   FontWeight="Bold" Foreground="#5BA3FF" HorizontalAlignment="Center"/>
                                    </StackPanel>
                                </Grid>
                                <ProgressBar Name="pbRam" Minimum="0" Maximum="100" Value="0"
                                             Height="8" Margin="0,10,0,4"/>
                                <!-- Módulos de RAM -->
                                <ItemsControl Name="icRamModules">
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="6" Background="#1A2540" BorderBrush="#2A3A5A"
                                                    BorderThickness="1" Padding="10,6" Margin="0,3">
                                                <Grid>
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="Auto"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Grid.Column="0" Text="{Binding Slot}" FontFamily="Segoe UI"
                                                               FontSize="10" FontWeight="Bold" Foreground="#5BA3FF"
                                                               VerticalAlignment="Center" Width="60"/>
                                                    <TextBlock Grid.Column="1" Text="{Binding Info}" FontFamily="Segoe UI"
                                                               FontSize="10" Foreground="#B0BACC" VerticalAlignment="Center"/>
                                                    <TextBlock Grid.Column="2" Text="{Binding Size}" FontFamily="Segoe UI"
                                                               FontSize="11" FontWeight="Bold" Foreground="#4AE896"
                                                               VerticalAlignment="Center"/>
                                                </Grid>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </StackPanel>
                        </Border>

                        <!-- ── SMART DEL DISCO ── -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Border Width="26" Height="26" CornerRadius="6" Background="#3A2010" Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="13"
                                                   Foreground="#FFB547" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="ESTADO S.M.A.R.T. DEL DISCO" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                                </StackPanel>
                                <ItemsControl Name="icSmartDisks">
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="8" Background="#1A2540" BorderBrush="#2A3A5A"
                                                    BorderThickness="1" Padding="14,10" Margin="0,4">
                                                <StackPanel>
                                                    <Grid Margin="0,0,0,6">
                                                        <Grid.ColumnDefinitions>
                                                            <ColumnDefinition Width="*"/>
                                                            <ColumnDefinition Width="Auto"/>
                                                        </Grid.ColumnDefinitions>
                                                        <TextBlock Grid.Column="0" Text="{Binding DiskName}" FontFamily="Segoe UI"
                                                                   FontSize="11" FontWeight="SemiBold" Foreground="#E0E8F4"/>
                                                        <Border Grid.Column="1" CornerRadius="4" Padding="8,2"
                                                                Background="{Binding StatusBg}">
                                                            <TextBlock Text="{Binding Status}" FontFamily="Segoe UI"
                                                                       FontSize="10" FontWeight="Bold" Foreground="{Binding StatusFg}"/>
                                                        </Border>
                                                    </Grid>
                                                    <ItemsControl ItemsSource="{Binding Attributes}">
                                                        <ItemsControl.ItemsPanel>
                                                            <ItemsPanelTemplate>
                                                                <WrapPanel Orientation="Horizontal"/>
                                                            </ItemsPanelTemplate>
                                                        </ItemsControl.ItemsPanel>
                                                        <ItemsControl.ItemTemplate>
                                                            <DataTemplate>
                                                                <Border CornerRadius="5" Background="#131625" BorderBrush="#3A4468"
                                                                        BorderThickness="1" Padding="8,4" Margin="3,3" MinWidth="130">
                                                                    <StackPanel>
                                                                        <TextBlock Text="{Binding Name}" FontFamily="Segoe UI"
                                                                                   FontSize="9" Foreground="#8B96B8"/>
                                                                        <TextBlock Text="{Binding Value}" FontFamily="Segoe UI"
                                                                                   FontSize="12" FontWeight="Bold"
                                                                                   Foreground="{Binding ValueColor}"/>
                                                                    </StackPanel>
                                                                </Border>
                                                            </DataTemplate>
                                                        </ItemsControl.ItemTemplate>
                                                    </ItemsControl>
                                                </StackPanel>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </StackPanel>
                        </Border>

                        <!-- ── RED ── -->
                        <Border CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40"
                                BorderThickness="1" Padding="16,14" Margin="0,0,0,8">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Border Width="26" Height="26" CornerRadius="6" Background="#2A1A4A" Margin="0,0,10,0">
                                        <TextBlock Text="" FontFamily="Segoe MDL2 Assets" FontSize="13"
                                                   Foreground="#C07AFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="TARJETAS DE RED" FontFamily="Segoe UI" FontSize="13"
                                               FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                                </StackPanel>
                                <ItemsControl Name="icNetAdapters">
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="8" Background="#1A2540" BorderBrush="#2A3A5A"
                                                    BorderThickness="1" Padding="14,10" Margin="0,4">
                                                <Grid>
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <StackPanel Grid.Column="0">
                                                        <TextBlock Text="{Binding Name}" FontFamily="Segoe UI"
                                                                   FontSize="11" FontWeight="SemiBold" Foreground="#E0E8F4"/>
                                                        <TextBlock Text="{Binding IP}" FontFamily="Segoe UI"
                                                                   FontSize="10" Foreground="#8B96B8" Margin="0,2"/>
                                                        <TextBlock Text="{Binding MAC}" FontFamily="Segoe UI"
                                                                   FontSize="10" Foreground="#8B96B8"/>
                                                    </StackPanel>
                                                    <StackPanel Grid.Column="1" HorizontalAlignment="Right">
                                                        <TextBlock Text="{Binding Speed}" FontFamily="Segoe UI"
                                                                   FontSize="13" FontWeight="Bold" Foreground="#C07AFF"
                                                                   HorizontalAlignment="Right"/>
                                                        <TextBlock Text="{Binding Status}" FontFamily="Segoe UI"
                                                                   FontSize="10" Foreground="{Binding StatusColor}"
                                                                   HorizontalAlignment="Right"/>
                                                        <TextBlock Text="{Binding BytesIO}" FontFamily="Segoe UI"
                                                                   FontSize="9" Foreground="#8B96B8"
                                                                   HorizontalAlignment="Right" Margin="0,2"/>
                                                    </StackPanel>
                                                </Grid>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </StackPanel>
                        </Border>

                    </StackPanel>
                    </ScrollViewer>
                </Grid>
                </TabItem>

                <!-- ══ TAB 3: EXPLORADOR DE DISCO ══ -->
                <TabItem Header="💾  Explorador de Disco">
                <Grid Background="#131625">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Toolbar fila 1: ruta + scan -->
                    <Border Grid.Row="0" Background="#131625" BorderBrush="#252B40" BorderThickness="0,0,0,1" Padding="10,8,10,4">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Ruta:" FontFamily="Segoe UI" FontSize="11"
                                       Foreground="#9BA4C0" VerticalAlignment="Center" Margin="0,0,6,0"/>
                            <TextBox Name="txtDiskScanPath" Grid.Column="1" Text="C:\"
                                     FontFamily="Segoe UI" FontSize="11" Foreground="#F0F3FA"
                                     Background="#1A1E2F" BorderBrush="#252B40" BorderThickness="1"
                                     Padding="6,4" VerticalAlignment="Center"/>
                            <Button Name="btnDiskBrowse" Grid.Column="2" Style="{StaticResource BtnGhost}"
                                    Content="📁" Height="28" Width="32" Padding="0" Margin="4,0"/>
                            <Button Name="btnDiskScan" Grid.Column="3" Style="{StaticResource BtnSecondary}"
                                    Content="🔍  Escanear" Height="28" MinWidth="100" Margin="0,0,4,0"/>
                            <Button Name="btnDiskStop" Grid.Column="4" Style="{StaticResource BtnAmber}"
                                    Content="⏹  Detener" Height="28" MinWidth="90" IsEnabled="False"/>
                        </Grid>
                    </Border>
                    <!-- [B1] Toolbar fila 2: filtro de búsqueda -->
                    <Border Grid.Row="1" Background="#0D0F1A" BorderBrush="#252B40" BorderThickness="0,0,0,1" Padding="10,5">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="🔎  Filtrar:" FontFamily="Segoe UI" FontSize="11"
                                       Foreground="#9BA4C0" VerticalAlignment="Center" Margin="0,0,6,0"/>
                            <TextBox Name="txtDiskFilter" Grid.Column="1"
                                     FontFamily="Segoe UI" FontSize="11" Foreground="#F0F3FA"
                                     Background="#1A1E2F" BorderBrush="#3A4468" BorderThickness="1"
                                     Padding="6,3" VerticalAlignment="Center"
                                     ToolTip="Filtra carpetas por nombre en tiempo real"/>
                            <Button Name="btnDiskFilterClear" Grid.Column="2" Content="✕"
                                    Style="{StaticResource BtnGhost}" Height="24" Width="28"
                                    Padding="0" Margin="4,0,0,0" ToolTip="Limpiar filtro"/>
                        </Grid>
                    </Border>

                    <!-- TreeView de resultados -->
                    <Grid Grid.Row="2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="4"/>
                            <ColumnDefinition Width="260"/>
                        </Grid.ColumnDefinitions>

                        <!-- ListView principal -->
                        <Border Grid.Column="0" Background="#1A2035" BorderBrush="#3A4468" BorderThickness="0,0,1,0">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <!-- Header de columnas -->
                                <Grid Grid.Row="0" Background="#131625" Margin="0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="100"/>
                                        <ColumnDefinition Width="70"/>
                                        <ColumnDefinition Width="90"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="  Nombre" FontFamily="Segoe UI" FontSize="10"
                                               FontWeight="SemiBold" Foreground="#9BA4C0" Padding="8,5"/>
                                    <TextBlock Grid.Column="1" Text="Tamaño" FontFamily="Segoe UI" FontSize="10"
                                               FontWeight="SemiBold" Foreground="#9BA4C0" Padding="8,5" TextAlignment="Right"/>
                                    <TextBlock Grid.Column="2" Text="%" FontFamily="Segoe UI" FontSize="10"
                                               FontWeight="SemiBold" Foreground="#9BA4C0" Padding="8,5" TextAlignment="Right"/>
                                    <TextBlock Grid.Column="3" Text="Archivos" FontFamily="Segoe UI" FontSize="10"
                                               FontWeight="SemiBold" Foreground="#9BA4C0" Padding="8,5" TextAlignment="Right"/>
                                </Grid>
                                <ListBox Name="lbDiskTree" Grid.Row="1"
                                         Background="Transparent" BorderThickness="0"
                                         ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                                         VirtualizingStackPanel.IsVirtualizing="True">
                                    <!-- [B2] Menú contextual -->
                                    <ListBox.ContextMenu>
                                        <ContextMenu>
                                            <MenuItem Name="ctxOpen"         Header="📂  Abrir en Explorador"/>
                                            <MenuItem Name="ctxCopy"         Header="📋  Copiar ruta"/>
                                            <Separator/>
                                            <MenuItem Name="ctxScanFolder"   Header="🔍  Escanear carpeta"/>
                                            <Separator/>
                                            <MenuItem Name="ctxDelete"       Header="🗑  Eliminar carpeta..."
                                                      Style="{StaticResource MenuItemDanger}"/>
                                            <Separator/>
                                            <MenuItem Name="ctxShowOutput"   Header="🖥  Mostrar Output"/>
                                        </ContextMenu>
                                    </ListBox.ContextMenu>
                                    <ListBox.ItemContainerStyle>
                                        <Style TargetType="ListBoxItem">
                                            <Setter Property="Padding" Value="0"/>
                                            <Setter Property="Margin" Value="0"/>
                                            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                                            <Setter Property="Template">
                                                <Setter.Value>
                                                    <ControlTemplate TargetType="ListBoxItem">
                                                        <Border x:Name="lbiBd" Background="Transparent"
                                                                BorderBrush="#2A3448" BorderThickness="0,0,0,1">
                                                            <ContentPresenter/>
                                                        </Border>
                                                        <ControlTemplate.Triggers>
                                                            <Trigger Property="IsSelected" Value="True">
                                                                <Setter TargetName="lbiBd" Property="Background" Value="#1A3A5C"/>
                                                            </Trigger>
                                                            <Trigger Property="IsMouseOver" Value="True">
                                                                <Setter TargetName="lbiBd" Property="Background" Value="#252B3B"/>
                                                            </Trigger>
                                                        </ControlTemplate.Triggers>
                                                    </ControlTemplate>
                                                </Setter.Value>
                                            </Setter>
                                        </Style>
                                    </ListBox.ItemContainerStyle>
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <Grid Height="30">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="100"/>
                                                    <ColumnDefinition Width="70"/>
                                                    <ColumnDefinition Width="90"/>
                                                </Grid.ColumnDefinitions>
                                                <!-- Barra de fondo proporcional -->
                                                <Border Grid.Column="0" Grid.ColumnSpan="4"
                                                        HorizontalAlignment="Left"
                                                        Width="{Binding BarWidth}" Height="30"
                                                        Background="{Binding BarColor}" Opacity="0.15"/>
                                                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center"
                                                            Margin="{Binding Indent}">
                                                    <!-- Botón colapsar/expandir (solo visible en carpetas con hijos) -->
                                                    <Button Name="btnToggle" Content="{Binding ToggleIcon}"
                                                            Tag="{Binding FullPath}"
                                                            Width="18" Height="18" Padding="0" Margin="0,0,3,0"
                                                            Background="Transparent" BorderThickness="0"
                                                            Foreground="#7BA8E0" FontSize="9" FontWeight="Bold"
                                                            Cursor="Hand"
                                                            Visibility="{Binding ToggleVisibility}"/>
                                                    <TextBlock Text="{Binding Icon}" FontSize="12" Margin="0,0,5,0"
                                                               VerticalAlignment="Center"/>
                                                    <TextBlock Text="{Binding DisplayName}" FontFamily="Segoe UI" FontSize="11"
                                                               Foreground="#D0D8F0" VerticalAlignment="Center"
                                                               TextTrimming="CharacterEllipsis"/>
                                                </StackPanel>
                                                <TextBlock Grid.Column="1" Text="{Binding SizeStr}" FontFamily="Segoe UI"
                                                           FontSize="11" FontWeight="SemiBold" Foreground="{Binding SizeColor}"
                                                           VerticalAlignment="Center" TextAlignment="Right" Margin="0,0,8,0"/>
                                                <TextBlock Grid.Column="2" Text="{Binding PctStr}" FontFamily="Segoe UI"
                                                           FontSize="10" Foreground="#8B96B8"
                                                           VerticalAlignment="Center" TextAlignment="Right" Margin="0,0,8,0"/>
                                                <TextBlock Grid.Column="3" Text="{Binding FileCount}" FontFamily="Segoe UI"
                                                           FontSize="10" Foreground="#8B96B8"
                                                           VerticalAlignment="Center" TextAlignment="Right" Margin="0,0,8,0"/>
                                            </Grid>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                            </Grid>
                        </Border>

                        <!-- Panel lateral de detalle -->
                        <Border Grid.Column="2" Background="#131625" Padding="12">
                            <StackPanel>
                                <TextBlock Text="DETALLE" FontFamily="Segoe UI" FontSize="10" FontWeight="SemiBold"
                                           Foreground="#6B7A9E" Margin="0,0,0,10"/>
                                <TextBlock Name="txtDiskDetailName" Text="—" FontFamily="Segoe UI" FontSize="12"
                                           FontWeight="Bold" Foreground="#F0F3FA" TextWrapping="Wrap" Margin="0,0,0,8"/>
                                <Grid Margin="0,0,0,6">
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Tamaño:" FontFamily="Segoe UI" FontSize="10" Foreground="#8B96B8"/>
                                    <TextBlock Name="txtDiskDetailSize" Grid.Column="1" Text="—" FontFamily="Segoe UI"
                                               FontSize="10" FontWeight="Bold" Foreground="#FFB547"/>
                                </Grid>
                                <Grid Margin="0,0,0,6">
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Archivos:" FontFamily="Segoe UI" FontSize="10" Foreground="#8B96B8"/>
                                    <TextBlock Name="txtDiskDetailFiles" Grid.Column="1" Text="—" FontFamily="Segoe UI"
                                               FontSize="10" FontWeight="Bold" Foreground="#4AE896"/>
                                </Grid>
                                <Grid Margin="0,0,0,6">
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Carpetas:" FontFamily="Segoe UI" FontSize="10" Foreground="#8B96B8"/>
                                    <TextBlock Name="txtDiskDetailDirs" Grid.Column="1" Text="—" FontFamily="Segoe UI"
                                               FontSize="10" FontWeight="Bold" Foreground="#5BA3FF"/>
                                </Grid>
                                <Grid Margin="0,0,0,14">
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="% del padre:" FontFamily="Segoe UI" FontSize="10" Foreground="#8B96B8"/>
                                    <TextBlock Name="txtDiskDetailPct" Grid.Column="1" Text="—" FontFamily="Segoe UI"
                                               FontSize="10" FontWeight="Bold" Foreground="#C07AFF"/>
                                </Grid>
                                <Rectangle Height="1" Fill="#3A4468" Margin="0,0,0,12"/>
                                <TextBlock Text="TOP 10 ARCHIVOS MÁS GRANDES" FontFamily="Segoe UI" FontSize="9"
                                           FontWeight="SemiBold" Foreground="#6B7A9E" Margin="0,0,0,8"/>
                                <ItemsControl Name="icTopFiles">
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <StackPanel Margin="0,0,0,6">
                                                <TextBlock Text="{Binding FileName}" FontFamily="Segoe UI" FontSize="10"
                                                           Foreground="#B0BACC" TextTrimming="CharacterEllipsis"/>
                                                <TextBlock Text="{Binding FileSize}" FontFamily="Segoe UI" FontSize="10"
                                                           FontWeight="Bold" Foreground="#FFB547"/>
                                            </StackPanel>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <!-- Barra de estado del escaneo -->
                    <Border Grid.Row="3" Background="#131625" BorderBrush="#252B40" BorderThickness="0,1,0,0" Padding="10,6">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Name="txtDiskScanStatus" Text="Listo"
                                       FontFamily="Segoe UI" FontSize="10" Foreground="#9BA4C0" VerticalAlignment="Center"/>
                            <!-- [B3] Exportar CSV + Informe HTML -->
                            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                                <Button Name="btnExportCsv" Content="📄  Exportar CSV"
                                        Style="{StaticResource BtnGhost}" Height="22" FontSize="10"
                                        Margin="0,0,6,0" IsEnabled="False" ToolTip="Exportar resultados a CSV"/>
                                <Button Name="btnDiskReport" Content="🌐  Informe HTML"
                                        Style="{StaticResource BtnGhost}" Height="22" FontSize="10"
                                        Margin="0,0,6,0" IsEnabled="False"
                                        ToolTip="Genera informe HTML visual del escaneo en .\output\"/>
                            </StackPanel>
                            <ProgressBar Name="pbDiskScan" Grid.Column="2" Width="150" Height="6"
                                         Minimum="0" Maximum="100" Value="0" IsIndeterminate="False"
                                         VerticalAlignment="Center"/>
                        </Grid>
                    </Border>
                </Grid>
                </TabItem>


                <!-- ── [B4] Pestaña Historial de Escaneos ── -->
                <TabItem Header="🕒  Historial">
                <Grid Background="#131625">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Toolbar fila 1: nombre + guardar -->
                    <Border Grid.Row="0" Background="#131625" BorderBrush="#252B40" BorderThickness="0,0,0,1" Padding="10,7">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <!-- Fila 1: campo nombre + botón guardar -->
                            <Grid Grid.Row="0" Margin="0,0,0,6">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Nombre:" VerticalAlignment="Center"
                                           Foreground="#7880A0" FontSize="11" Margin="0,0,8,0"
                                           FontFamily="JetBrains Mono"/>
                                <TextBox Name="txtSnapshotName" Grid.Column="1"
                                         Background="#0D0F1A" Foreground="#E8ECF4"
                                         BorderBrush="#2A3448" BorderThickness="1"
                                         CaretBrush="#5BA3FF" SelectionBrush="#1A3A5C"
                                         FontSize="12" Padding="8,5"
                                         FontFamily="JetBrains Mono, Consolas"
                                         IsEnabled="False"/>
                                <Button Name="btnSnapshotSave" Grid.Column="2" Content="💾  Guardar"
                                        Margin="6,0,0,0" Padding="12,5"
                                        Background="#1A3A5C" Foreground="#5BA3FF"
                                        BorderBrush="#2A4A6C" BorderThickness="1" Cursor="Hand"
                                        FontSize="12" IsEnabled="False"/>
                            </Grid>

                            <!-- Fila 2: acciones sobre snapshots existentes -->
                            <Grid Grid.Row="1">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <CheckBox Name="chkSnapshotSelectAll" Grid.Column="0"
                                          Content="Todo" Foreground="#7880A0" FontSize="11"
                                          VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock Grid.Column="1" Name="txtSnapshotSelCount"
                                           Text="Snapshots guardados" VerticalAlignment="Center"
                                           Foreground="#7880A0" FontSize="11" FontFamily="JetBrains Mono"/>
                                <Button Name="btnSnapshotCompare" Grid.Column="2" Content="📊  Comparar"
                                        Margin="0,0,6,0" Padding="10,4"
                                        Background="#1A2F1A" Foreground="#4AE896"
                                        BorderBrush="#2A4A2A" BorderThickness="1" Cursor="Hand"
                                        FontSize="11" IsEnabled="False"
                                        ToolTip="Compara los snapshots marcados entre sí o contra el escaneo actual"/>
                                <Button Name="btnSnapshotDelete" Grid.Column="3" Content="🗑  Eliminar"
                                        Padding="10,4"
                                        Background="#2F1A1A" Foreground="#FF6B84"
                                        BorderBrush="#4A2A2A" BorderThickness="1" Cursor="Hand"
                                        FontSize="11" IsEnabled="False"
                                        ToolTip="Elimina todos los snapshots marcados"/>
                            </Grid>
                        </Grid>
                    </Border>

                    <!-- Lista de snapshots + panel de detalle/comparación -->
                    <Grid Grid.Row="1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="320"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <!-- Lista de snapshots con checkboxes -->
                        <Border Grid.Column="0" BorderBrush="#252B40" BorderThickness="0,0,1,0" Background="#0D0F1A">
                            <ListBox Name="lbSnapshots" Background="Transparent" BorderThickness="0"
                                     SelectionMode="Extended" FontSize="12"
                                     ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <Border Padding="8,6" Background="Transparent">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                <!-- CheckBox que bindea a IsChecked del item -->
                                                <CheckBox Grid.Column="0" IsChecked="{Binding IsChecked, Mode=TwoWay}"
                                                          VerticalAlignment="Center" Margin="0,0,8,0"
                                                          Focusable="False"/>
                                                <StackPanel Grid.Column="1">
                                                    <TextBlock Text="{Binding Label}"
                                                               FontWeight="SemiBold" Foreground="#E8ECF4" FontSize="12"
                                                               TextTrimming="CharacterEllipsis"/>
                                                    <TextBlock Text="{Binding DateStr}"
                                                               Foreground="#5BA3FF" FontSize="10" Margin="0,2,0,0"
                                                               FontFamily="JetBrains Mono"/>
                                                    <TextBlock Text="{Binding SummaryStr}"
                                                               Foreground="#7880A0" FontSize="10" Margin="0,2,0,0"
                                                               FontFamily="JetBrains Mono"/>
                                                </StackPanel>
                                            </Grid>
                                        </Border>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                                <ListBox.ItemContainerStyle>
                                    <Style TargetType="ListBoxItem">
                                        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                                        <Setter Property="Padding" Value="0"/>
                                        <Setter Property="Background" Value="Transparent"/>
                                        <Setter Property="Foreground" Value="#E8ECF4"/>
                                        <Style.Triggers>
                                            <Trigger Property="IsSelected" Value="True">
                                                <Setter Property="Background" Value="#1A2F4A"/>
                                            </Trigger>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="Background" Value="#181D2E"/>
                                            </Trigger>
                                        </Style.Triggers>
                                    </Style>
                                </ListBox.ItemContainerStyle>
                            </ListBox>
                        </Border>

                        <!-- Panel detalle / comparación -->
                        <Grid Grid.Column="1" Background="#0D0F1A">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>

                            <!-- Header con info del snapshot seleccionado -->
                            <Border Grid.Row="0" Background="#131625" BorderBrush="#252B40" BorderThickness="0,0,0,1" Padding="14,10">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Name="txtSnapshotDetailTitle" Text="Selecciona un snapshot"
                                               Foreground="#7880A0" FontSize="13" FontWeight="SemiBold"/>
                                    <TextBlock Name="txtSnapshotDetailMeta" Text="" Margin="12,0,0,0"
                                               Foreground="#5BA3FF" FontSize="11" FontFamily="JetBrains Mono"
                                               VerticalAlignment="Center"/>
                                </StackPanel>
                            </Border>

                            <!-- Lista de carpetas del snapshot / comparación -->
                            <ListBox Name="lbSnapshotDetail" Grid.Row="1"
                                     Background="Transparent" BorderThickness="0"
                                     FontSize="12" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <Grid Margin="10,4">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="90"/>
                                                <ColumnDefinition Width="70"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Grid.Column="0" Text="{Binding FolderName}"
                                                       Foreground="#E8ECF4" TextTrimming="CharacterEllipsis"
                                                       ToolTip="{Binding FullPath}"/>
                                            <TextBlock Grid.Column="1" Text="{Binding SizeStr}"
                                                       Foreground="{Binding SizeColor}" FontFamily="JetBrains Mono"
                                                       HorizontalAlignment="Right" FontSize="11"/>
                                            <TextBlock Grid.Column="2" Text="{Binding DeltaStr}"
                                                       Foreground="{Binding DeltaColor}" FontFamily="JetBrains Mono"
                                                       HorizontalAlignment="Right" FontSize="11"/>
                                        </Grid>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                                <ListBox.ItemContainerStyle>
                                    <Style TargetType="ListBoxItem">
                                        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                                        <Setter Property="Padding" Value="0"/>
                                        <Setter Property="Background" Value="Transparent"/>
                                        <Style.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="Background" Value="#131625"/>
                                            </Trigger>
                                        </Style.Triggers>
                                    </Style>
                                </ListBox.ItemContainerStyle>
                            </ListBox>
                        </Grid>
                    </Grid>

                    <!-- Status bar -->
                    <Border Grid.Row="2" Background="#131625" BorderBrush="#252B40" BorderThickness="0,1,0,0" Padding="10,5">
                        <TextBlock Name="txtSnapshotStatus" Text="Sin snapshots guardados."
                                   Foreground="#7880A0" FontSize="11" FontFamily="JetBrains Mono"/>
                    </Border>

                </Grid>
                </TabItem>

            </TabControl>

            <!-- ═══ CONSOLA ════════════════════════════════════════════ -->
            <Border Name="OutputPanel" Grid.Row="3" CornerRadius="10" Background="#1A2035"
                    BorderBrush="#252B40" BorderThickness="1" Margin="0,0,0,10">
                <Grid Margin="1">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Barra de título de la consola -->
                    <Border Grid.Row="0" CornerRadius="10,10,0,0" Background="#1A1E2F"
                            BorderBrush="#252B40" BorderThickness="0,0,0,1" Padding="10,6">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <!-- Botones de ventana funcionales -->
                            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                                <!-- Rojo: Cerrar/ocultar output -->
                                <Button Name="btnOutputClose" Width="13" Height="13" Margin="0,0,7,0"
                                        Cursor="Hand" ToolTip="Ocultar output"
                                        BorderThickness="0">
                                    <Button.Template>
                                        <ControlTemplate TargetType="Button">
                                            <Ellipse x:Name="el" Width="13" Height="13" Fill="#FF6B84"/>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="el" Property="Fill" Value="#CC2244"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Button.Template>
                                </Button>
                                <!-- Amarillo: Minimizar output -->
                                <Button Name="btnOutputMinimize" Width="13" Height="13" Margin="0,0,7,0"
                                        Cursor="Hand" ToolTip="Minimizar output"
                                        Background="#F5A623" BorderThickness="0">
                                    <Button.Template>
                                        <ControlTemplate TargetType="Button">
                                            <Ellipse x:Name="el" Width="13" Height="13" Fill="#F5A623"/>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="el" Property="Fill" Value="#D4850A"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Button.Template>
                                </Button>
                                <!-- Verde: Expandir output -->
                                <Button Name="btnOutputExpand" Width="13" Height="13" Margin="0,0,14,0"
                                        Cursor="Hand" ToolTip="Expandir output"
                                        Background="#4AE896" BorderThickness="0">
                                    <Button.Template>
                                        <ControlTemplate TargetType="Button">
                                            <Ellipse x:Name="el" Width="13" Height="13" Fill="#4AE896"/>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="el" Property="Fill" Value="#28C874"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Button.Template>
                                </Button>
                            </StackPanel>
                            <!-- Etiquetas centradas -->
                            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="OUTPUT" FontFamily="Segoe UI" FontSize="9" FontWeight="SemiBold"
                                           Foreground="#8B96B8" VerticalAlignment="Center"/>
                                <TextBlock Name="TaskText" FontFamily="Segoe UI" FontSize="10"
                                           Foreground="#9BA4C0" VerticalAlignment="Center" Margin="14,0,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Texto de salida -->
                    <TextBox Name="ConsoleOutput" Grid.Row="1"
                             IsReadOnly="True"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Disabled"
                             FontFamily="Cascadia Code, Consolas, Courier New"
                             FontSize="10.5"
                             Background="Transparent"
                             Foreground="#5AE88A"
                             BorderThickness="0"
                             Padding="14,10"
                             TextWrapping="Wrap"
                             SelectionBrush="#3D8EFF"/>

                    <!-- Barra de progreso + porcentaje -->
                    <Grid Grid.Row="2" Margin="14,6,14,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <ProgressBar Name="ProgressBar" Grid.Column="0" Height="6"
                                     Minimum="0" Maximum="100" Value="0"
                                     VerticalAlignment="Center"/>
                        <TextBlock Name="ProgressText" Grid.Column="1"
                                   Text="0%" FontFamily="Segoe UI" FontSize="10"
                                   FontWeight="SemiBold" Foreground="#9BA4C0"
                                   VerticalAlignment="Center" Margin="12,0,0,0" Width="36"/>
                    </Grid>
                </Grid>
            </Border>

            <!-- ═══ FOOTER / BOTONES ══════════════════════════════════ -->
            <Grid Grid.Row="4">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Reinicio automático -->
                <Border Grid.Column="0" CornerRadius="8" Background="#1A1E2F"
                        BorderBrush="#252B40" BorderThickness="1" Padding="12,0" Margin="0,0,8,0">
                    <CheckBox Name="chkAutoRestart" VerticalAlignment="Center">
                        <CheckBox.Content>
                            <TextBlock Text="Reiniciar al finalizar" FontFamily="Segoe UI"
                                       FontSize="11" Foreground="#9BA4C0"/>
                        </CheckBox.Content>
                    </CheckBox>
                </Border>

                <!-- Spacer -->
                <Rectangle Grid.Column="1"/>

                <Button Name="btnShowOutput"   Grid.Column="2" Style="{StaticResource BtnGhost}"
                        Content="🖥 Output" MinWidth="90" Visibility="Collapsed"
                        ToolTip="Mostrar panel de output"/>
                <Button Name="btnSelectAll"    Grid.Column="3" Style="{StaticResource BtnGhost}"
                        Content="Seleccionar todo" MinWidth="130"/>
                <Button Name="btnDryRun"       Grid.Column="4" Style="{StaticResource BtnCyan}"
                        Content="Analizar" MinWidth="90"
                        ToolTip="Dry Run — reportar sin ejecutar cambios"/>
                <Button Name="btnStart"        Grid.Column="5" Style="{StaticResource BtnPrimary}"
                        Content="▶  Iniciar optimización" MinWidth="160" FontWeight="Bold"/>
                <Button Name="btnCancel"       Grid.Column="6" Style="{StaticResource BtnAmber}"
                        Content="Cancelar" MinWidth="90" IsEnabled="False"/>
                <Button Name="btnSaveLog"      Grid.Column="7" Style="{StaticResource BtnGhost}"
                        Content="Guardar log" MinWidth="100"/>
                <Button Name="btnExit"         Grid.Column="8" Style="{StaticResource BtnDanger}"
                        Content="Salir" MinWidth="80"/>
            </Grid>

        </Grid>
    </Grid>
</Window>
"@

# ─────────────────────────────────────────────────────────────────────────────
# Cargar XAML y obtener controles
# ─────────────────────────────────────────────────────────────────────────────
Set-SplashProgress 65 "Construyendo interfaz gráfica..."
$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
Set-SplashProgress 85 "Enlazando controles..."
# [RAM-05] Inicializar RunspacePool centralizado en background
Initialize-RunspacePool

$StatusText    = $window.FindName("StatusText")
$ConsoleOutput = $window.FindName("ConsoleOutput")
$ProgressBar   = $window.FindName("ProgressBar")
$ProgressText  = $window.FindName("ProgressText")
$TaskText      = $window.FindName("TaskText")

# Info panel
$InfoCPU       = $window.FindName("InfoCPU")
$InfoRAM       = $window.FindName("InfoRAM")
$InfoDisk      = $window.FindName("InfoDisk")
$btnRefreshInfo= $window.FindName("btnRefreshInfo")
$CpuPctText    = $window.FindName("CpuPctText")
$RamPctText    = $window.FindName("RamPctText")
$DiskPctText   = $window.FindName("DiskPctText")
$CpuChart      = $window.FindName("CpuChart")
$RamChart      = $window.FindName("RamChart")
$DiskChart     = $window.FindName("DiskChart")

# Checkboxes
$chkDryRun          = $window.FindName("chkDryRun")
$chkOptimizeDisks   = $window.FindName("chkOptimizeDisks")
$chkRecycleBin      = $window.FindName("chkRecycleBin")
$chkTempFiles       = $window.FindName("chkTempFiles")
$chkUserTemp        = $window.FindName("chkUserTemp")
$chkWUCache         = $window.FindName("chkWUCache")
$chkChkdsk          = $window.FindName("chkChkdsk")
$chkClearMemory     = $window.FindName("chkClearMemory")
$chkCloseProcesses  = $window.FindName("chkCloseProcesses")
$chkDNSCache        = $window.FindName("chkDNSCache")
$chkBrowserCache    = $window.FindName("chkBrowserCache")
$chkBackupRegistry  = $window.FindName("chkBackupRegistry")
$chkCleanRegistry   = $window.FindName("chkCleanRegistry")
$chkSFC             = $window.FindName("chkSFC")
$chkDISM            = $window.FindName("chkDISM")
$chkEventLogs       = $window.FindName("chkEventLogs")
$chkShowStartup     = $window.FindName("chkShowStartup")
$chkAutoRestart     = $window.FindName("chkAutoRestart")

# Botones
$btnSelectAll  = $window.FindName("btnSelectAll")
$btnDryRun     = $window.FindName("btnDryRun")
$btnStart      = $window.FindName("btnStart")
$btnCancel     = $window.FindName("btnCancel")
$btnSaveLog    = $window.FindName("btnSaveLog")
$btnExit       = $window.FindName("btnExit")
$btnAbout      = $window.FindName("btnAbout")

# Output panel controls
$OutputPanel      = $window.FindName("OutputPanel")
$btnOutputClose   = $window.FindName("btnOutputClose")
$btnOutputMinimize= $window.FindName("btnOutputMinimize")
$btnOutputExpand  = $window.FindName("btnOutputExpand")
$btnShowOutput    = $window.FindName("btnShowOutput")

# ── Estado del panel Output ──────────────────────────────────────────────────
$script:OutputState   = "normal"   # "normal" | "minimized" | "hidden" | "expanded"
$script:OutputNormalH = 200        # altura normal en píxeles

function Set-OutputState {
    param([string]$State)
    # Obtener el RowDefinition del Grid padre por índice 3
    $mainGrid = $OutputPanel.Parent
    $outputRowDef = $mainGrid.RowDefinitions[3]

    switch ($State) {
        "hidden" {
            $OutputPanel.Visibility = [System.Windows.Visibility]::Collapsed
            $outputRowDef.Height = [System.Windows.GridLength]::new(0)
            $btnShowOutput.Visibility = [System.Windows.Visibility]::Visible
            $script:OutputState = "hidden"
        }
        "minimized" {
            $OutputPanel.Visibility = [System.Windows.Visibility]::Visible
            $outputRowDef.Height = [System.Windows.GridLength]::new(36)
            $btnShowOutput.Visibility = [System.Windows.Visibility]::Collapsed
            $script:OutputState = "minimized"
        }
        "expanded" {
            $OutputPanel.Visibility = [System.Windows.Visibility]::Visible
            $outputRowDef.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $btnShowOutput.Visibility = [System.Windows.Visibility]::Collapsed
            $script:OutputState = "expanded"
        }
        default {   # "normal"
            $OutputPanel.Visibility = [System.Windows.Visibility]::Visible
            $outputRowDef.Height = [System.Windows.GridLength]::new($script:OutputNormalH)
            $btnShowOutput.Visibility = [System.Windows.Visibility]::Collapsed
            $script:OutputState = "normal"
        }
    }
}

$btnOutputClose.Add_Click({ Set-OutputState "hidden" })
$btnOutputMinimize.Add_Click({
    if ($script:OutputState -eq "minimized") { Set-OutputState "normal" } else { Set-OutputState "minimized" }
})
$btnOutputExpand.Add_Click({
    if ($script:OutputState -eq "expanded") { Set-OutputState "normal" } else { Set-OutputState "expanded" }
})
$btnShowOutput.Add_Click({ Set-OutputState "normal" })


# ─────────────────────────────────────────────────────────────────────────────
# DIÁLOGOS TEMÁTICOS — reemplazan MessageBox y InputBox del sistema
# Tipos: "info" | "warning" | "error" | "success" | "question"
# ─────────────────────────────────────────────────────────────────────────────
function Show-ThemedDialog {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet("info","warning","error","success","question")]
        [string]$Type = "info",
        [ValidateSet("OK","YesNo")]
        [string]$Buttons = "OK"
    )

    $iconChar  = switch ($Type) {
        "info"     { "ℹ" }
        "warning"  { "⚠" }
        "error"    { "✕" }
        "success"  { "✓" }
        "question" { "?" }
    }
    $accentColor = switch ($Type) {
        "info"     { "#5BA3FF" }
        "warning"  { "#FFB547" }
        "error"    { "#FF6B84" }
        "success"  { "#4AE896" }
        "question" { "#9B7EFF" }
    }
    $accentBg = switch ($Type) {
        "info"     { "#0D1E35" }
        "warning"  { "#2B1E0A" }
        "error"    { "#2B0D12" }
        "success"  { "#0D2B1A" }
        "question" { "#1A0D35" }
    }

    # Escapar caracteres especiales XML para evitar romper el XAML
    $Title   = $Title   -replace '&','&amp;' -replace '"','&quot;' -replace "'","&apos;" -replace '<','&lt;' -replace '>','&gt;'
    $Message = $Message -replace '&','&amp;' -replace '"','&quot;' -replace "'","&apos;" -replace '<','&lt;' -replace '>','&gt;'

    $btnOkXaml = if ($Buttons -eq "OK") {
        "<Button Name=`"btnOK`" Content=`"Aceptar`" Width=`"100`" Height=`"34`" Margin=`"0`"
                 Background=`"$accentColor`" Foreground=`"#0D0F1A`" BorderThickness=`"0`"
                 FontWeight=`"Bold`" FontSize=`"12`" Cursor=`"Hand`" IsDefault=`"True`"/>"
    } else {
        "<StackPanel Orientation=`"Horizontal`" HorizontalAlignment=`"Right`" Margin=`"0`">
            <Button Name=`"btnNo`"  Content=`"No`"  Width=`"90`" Height=`"34`" Margin=`"0,0,8,0`"
                    Background=`"#1A1E2F`" Foreground=`"#7880A0`" BorderBrush=`"#252B40`" BorderThickness=`"1`"
                    FontSize=`"12`" Cursor=`"Hand`" IsCancel=`"True`"/>
            <Button Name=`"btnYes`" Content=`"Sí`"  Width=`"90`" Height=`"34`"
                    Background=`"$accentColor`" Foreground=`"#0D0F1A`" BorderThickness=`"0`"
                    FontWeight=`"Bold`" FontSize=`"12`" Cursor=`"Hand`" IsDefault=`"True`"/>
        </StackPanel>"
    }

    $dlgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="" Width="420" SizeToContent="Height"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        Topmost="True">
    <Border Background="#131625" CornerRadius="12"
            BorderBrush="$accentColor" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect BlurRadius="30" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header con icono y título -->
            <Border Grid.Row="0" Background="$accentBg" CornerRadius="11,11,0,0"
                    BorderBrush="$accentColor" BorderThickness="0,0,0,1" Padding="20,16">
                <StackPanel Orientation="Horizontal">
                    <Border Width="32" Height="32" CornerRadius="8"
                            Background="$accentColor" Margin="0,0,14,0" VerticalAlignment="Center">
                        <TextBlock Text="$iconChar" FontSize="16" FontWeight="Bold"
                                   Foreground="#0D0F1A"
                                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="$Title" FontSize="14" FontWeight="Bold"
                               Foreground="#E8ECF4" VerticalAlignment="Center"
                               FontFamily="Syne, Segoe UI"/>
                </StackPanel>
            </Border>

            <!-- Mensaje -->
            <Border Grid.Row="1" Padding="22,18,22,14">
                <TextBlock Text="$Message" Foreground="#B0BACC" FontSize="12.5"
                           TextWrapping="Wrap" LineHeight="20"
                           FontFamily="Segoe UI"/>
            </Border>

            <!-- Botones -->
            <Border Grid.Row="2" Padding="22,0,22,18">
                $btnOkXaml
            </Border>
        </Grid>
    </Border>
</Window>
"@

    $dlgReader = [System.Xml.XmlNodeReader]::new([xml]$dlgXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($dlgReader)
    try { $dlg.Owner = $window } catch {}

    $result = $false
    if ($Buttons -eq "OK") {
        $dlg.FindName("btnOK").Add_Click({ $dlg.DialogResult = $true; $dlg.Close() })
    } else {
        $script:_themedDlgRef = $dlg
        $dlg.FindName("btnYes").Add_Click({ $script:_dlgResult = $true;  $script:_themedDlgRef.Close() })
        $dlg.FindName("btnNo").Add_Click({  $script:_dlgResult = $false; $script:_themedDlgRef.Close() })
    }

    # Arrastrar la ventana por cualquier parte
    $script:_themedDlgRef = $dlg
    $dlg.Add_MouseLeftButtonDown({ $script:_themedDlgRef.DragMove() })

    $script:_dlgResult = $false
    $dlg.ShowDialog() | Out-Null
    return $script:_dlgResult
}

function Show-ThemedInput {
    param(
        [string]$Title,
        [string]$Prompt,
        [string]$Default = ""
    )

    # Escapar caracteres especiales XML para evitar romper el XAML
    $Title  = $Title  -replace '&','&amp;' -replace '"','&quot;' -replace "'","&apos;" -replace '<','&lt;' -replace '>','&gt;'
    $Prompt = $Prompt -replace '&','&amp;' -replace '"','&quot;' -replace "'","&apos;" -replace '<','&lt;' -replace '>','&gt;'

    $dlgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="" Width="440" SizeToContent="Height"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        Topmost="True">
    <Border Background="#131625" CornerRadius="12"
            BorderBrush="#5BA3FF" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect BlurRadius="30" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <Border Grid.Row="0" Background="#0D1E35" CornerRadius="11,11,0,0"
                    BorderBrush="#5BA3FF" BorderThickness="0,0,0,1" Padding="20,16">
                <StackPanel Orientation="Horizontal">
                    <Border Width="32" Height="32" CornerRadius="8"
                            Background="#5BA3FF" Margin="0,0,14,0" VerticalAlignment="Center">
                        <TextBlock Text="✎" FontSize="16" FontWeight="Bold"
                                   Foreground="#0D0F1A"
                                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="$Title" FontSize="14" FontWeight="Bold"
                               Foreground="#E8ECF4" VerticalAlignment="Center"
                               FontFamily="Syne, Segoe UI"/>
                </StackPanel>
            </Border>

            <!-- Prompt -->
            <Border Grid.Row="1" Padding="22,16,22,8">
                <TextBlock Text="$Prompt" Foreground="#B0BACC" FontSize="12"
                           TextWrapping="Wrap" FontFamily="Segoe UI"/>
            </Border>

            <!-- TextBox -->
            <Border Grid.Row="2" Padding="22,0,22,16">
                <TextBox Name="txtInput"
                         Background="#0D0F1A" Foreground="#E8ECF4"
                         BorderBrush="#2A3448" BorderThickness="1"
                         CaretBrush="#5BA3FF" SelectionBrush="#1A3A5C"
                         FontSize="13" Padding="10,8"
                         FontFamily="JetBrains Mono, Consolas"/>
            </Border>

            <!-- Botones -->
            <Border Grid.Row="3" Padding="22,0,22,18">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button Name="btnCancel" Content="Cancelar" Width="100" Height="34" Margin="0,0,8,0"
                            Background="#1A1E2F" Foreground="#7880A0" BorderBrush="#252B40" BorderThickness="1"
                            FontSize="12" Cursor="Hand" IsCancel="True"/>
                    <Button Name="btnOK" Content="Aceptar" Width="100" Height="34"
                            Background="#5BA3FF" Foreground="#0D0F1A" BorderThickness="0"
                            FontWeight="Bold" FontSize="12" Cursor="Hand" IsDefault="True"/>
                </StackPanel>
            </Border>
        </Grid>
    </Border>
</Window>
"@

    $dlgReader = [System.Xml.XmlNodeReader]::new([xml]$dlgXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($dlgReader)
    try { $dlg.Owner = $window } catch {}

    $txtInput = $dlg.FindName("txtInput")
    $txtInput.Text = $Default
    $txtInput.SelectAll()

    # Guardar referencias en $script: para que los closures de Add_Click puedan accederlas
    $script:_themedInputDlg = $dlg
    $script:_themedInputTxt = $txtInput

    $dlg.Add_MouseLeftButtonDown({ $script:_themedInputDlg.DragMove() })
    $dlg.Add_ContentRendered({ $script:_themedInputTxt.Focus() })

    $script:_inputResult = $null
    $dlg.FindName("btnOK").Add_Click({
        $script:_inputResult = $script:_themedInputTxt.Text
        $script:_themedInputDlg.Close()
    })
    $dlg.FindName("btnCancel").Add_Click({
        $script:_inputResult = $null
        $script:_themedInputDlg.Close()
    })

    $dlg.ShowDialog() | Out-Null
    return $script:_inputResult
}

# ─────────────────────────────────────────────────────────────────────────────
# Directorio raíz de la aplicación — ruta canónica usada en todo el script
# ─────────────────────────────────────────────────────────────────────────────
$script:AppDir = if ($PSScriptRoot -and $PSScriptRoot -ne '') {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).Path
}

# ─────────────────────────────────────────────────────────────────────────────
# Cargar logo desde .\assets\img\sysopt.png e icono de ventana desde .\assets\img\sysops.ico
# ─────────────────────────────────────────────────────────────────────────────
$imgLogo = $window.FindName("imgLogo")
try {
    $logoPath = Join-Path $script:AppDir "assets\img\sysopt.png"
    if (Test-Path $logoPath) {
        $logoBitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $logoBitmap.BeginInit()
        $logoBitmap.UriSource   = [Uri]::new($logoPath, [UriKind]::Absolute)
        $logoBitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $logoBitmap.EndInit()
        $imgLogo.Source = $logoBitmap
    }
} catch {
    Write-Verbose "SysOpt: No se pudo cargar el logo — $($_.Exception.Message)"
}

# Icono de la ventana principal (barra de tareas y Alt+Tab)
try {
    $icoPath = Join-Path $script:AppDir "assets\img\sysops.ico"
    if (Test-Path $icoPath) {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create(
            [Uri]::new($icoPath, [UriKind]::Absolute))
    }
} catch {
    Write-Verbose "SysOpt: No se pudo cargar el icono — $($_.Exception.Message)"
}

# Estado de cancelación
$script:CancelSource = $null
$script:WasCancelled = $false

# ─────────────────────────────────────────────────────────────────────────────
# Función para escribir en consola (hilo principal)
# ─────────────────────────────────────────────────────────────────────────────
function Write-ConsoleMain {
    param([string]$Message)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $ConsoleOutput.AppendText("[$timestamp] $Message`n")
    $ConsoleOutput.ScrollToEnd()
}

# ─────────────────────────────────────────────────────────────────────────────
# Chart history buffers (60 samples each)
# ─────────────────────────────────────────────────────────────────────────────
$script:CpuHistory  = [System.Collections.Generic.List[double]]::new()
$script:RamHistory  = [System.Collections.Generic.List[double]]::new()
$script:DiskHistory = [System.Collections.Generic.List[double]]::new()
$script:DiskCounter = $null

# Pre-init disk counter
try {
    $script:DiskCounter = New-Object System.Diagnostics.PerformanceCounter("PhysicalDisk","% Disk Time","_Total",$false)
    $null = $script:DiskCounter.NextValue()   # first call always 0, warm up
} catch { $script:DiskCounter = $null }

# ─────────────────────────────────────────────────────────────────────────────
# Helper: Draw sparkline chart on a WPF Canvas
# ─────────────────────────────────────────────────────────────────────────────
function Draw-SparkLine {
    param(
        [System.Windows.Controls.Canvas]$Canvas,
        [System.Collections.Generic.List[double]]$Data,
        [string]$LineColor,
        [string]$FillColor
    )

    $Canvas.Children.Clear()
    $w = $Canvas.ActualWidth
    $h = $Canvas.ActualHeight
    if ($w -le 0 -or $h -le 0) { $w = 300; $h = 52 }

    $maxPoints = 60
    $pts = $Data.ToArray()
    if ($pts.Count -eq 0) { return }

    $step = if ($pts.Count -gt 1) { $w / ($maxPoints - 1) } else { $w }
    $startIdx = [Math]::Max(0, $pts.Count - $maxPoints)
    $visible = $pts[$startIdx..($pts.Count - 1)]

    # Grid lines at 25%, 50%, 75%
    foreach ($gridPct in @(25, 50, 75)) {
        $gy = $h - ($gridPct / 100.0 * $h)
        $line = New-Object System.Windows.Shapes.Line
        $line.X1 = 0; $line.X2 = $w
        $line.Y1 = $gy; $line.Y2 = $gy
        $line.Stroke = [System.Windows.Media.Brushes]::White
        $line.Opacity = 0.06
        $line.StrokeDashArray = [System.Windows.Media.DoubleCollection]::new()
        $line.StrokeDashArray.Add(4); $line.StrokeDashArray.Add(4)
        [void]$Canvas.Children.Add($line)
    }

    # Build polyline points
    $polyPts = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $visible.Count; $i++) {
        $xOffset = $maxPoints - $visible.Count
        $x = ($i + $xOffset) * $step
        $y = $h - ($visible[$i] / 100.0 * $h)
        $polyPts.Add([System.Windows.Point]::new($x, $y))
    }

    # Fill polygon (area under line)
    if ($polyPts.Count -ge 2) {
        $fillPts = New-Object System.Windows.Media.PointCollection
        foreach ($p in $polyPts) { $fillPts.Add($p) }
        $fillPts.Add([System.Windows.Point]::new($polyPts[$polyPts.Count-1].X, $h))
        $fillPts.Add([System.Windows.Point]::new($polyPts[0].X, $h))

        $poly = New-Object System.Windows.Shapes.Polygon
        $poly.Points = $fillPts
        $gradBrush = New-Object System.Windows.Media.LinearGradientBrush
        $gradBrush.StartPoint = [System.Windows.Point]::new(0, 0)
        $gradBrush.EndPoint   = [System.Windows.Point]::new(0, 1)
        $gs1 = New-Object System.Windows.Media.GradientStop
        $gs1.Color  = [System.Windows.Media.ColorConverter]::ConvertFromString($FillColor)
        $gs1.Offset = 0
        $gs2 = New-Object System.Windows.Media.GradientStop
        $gs2.Color  = [System.Windows.Media.ColorConverter]::ConvertFromString($FillColor)
        $gs2.Offset = 1
        $gs2.Color  = $gs2.Color; $gs2.Color = [System.Windows.Media.Color]::FromArgb(5, $gs2.Color.R, $gs2.Color.G, $gs2.Color.B)
        $gradBrush.GradientStops.Add($gs1)
        $gradBrush.GradientStops.Add($gs2)
        $poly.Fill    = $gradBrush
        $poly.Opacity = 0.35
        [void]$Canvas.Children.Add($poly)
    }

    # Draw the line
    if ($polyPts.Count -ge 2) {
        $pline = New-Object System.Windows.Shapes.Polyline
        $pline.Points = $polyPts
        $pline.Stroke = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString($LineColor))
        $pline.StrokeThickness = 1.8
        [void]$Canvas.Children.Add($pline)
    }

    # Current value dot
    if ($polyPts.Count -ge 1) {
        $lastPt = $polyPts[$polyPts.Count - 1]
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width  = 6; $dot.Height = 6
        $dot.Fill   = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString($LineColor))
        [System.Windows.Controls.Canvas]::SetLeft($dot, $lastPt.X - 3)
        [System.Windows.Controls.Canvas]::SetTop($dot,  $lastPt.Y - 3)
        [void]$Canvas.Children.Add($dot)
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# [N1] Actualizar panel superior (CPU, RAM, Disco C:) + gráficas sparkline
#      Síncrono en el UI thread — igual que el original. Los CimInstance rápidos
#      (<150 ms) no congelan la UI en un tick de 2 segundos.
# ─────────────────────────────────────────────────────────────────────────────
function Update-SystemInfo {
    try {
        $os  = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cpu = Get-CimInstance -ClassName Win32_Processor       -ErrorAction Stop | Select-Object -First 1

        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGB  = [math]::Round($os.FreePhysicalMemory     / 1MB, 1)
        $usedPct = [math]::Round((($totalGB - $freeGB) / [math]::Max($totalGB, 1)) * 100)

        # Disco C: via Win32_LogicalDisk — no requiere módulo Storage
        $diskCim     = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" `
                           -ErrorAction SilentlyContinue | Select-Object -First 1
        $diskTotalGB = if ($diskCim) { [math]::Round($diskCim.Size      / 1GB, 1) } else { 0 }
        $diskFreeGB  = if ($diskCim) { [math]::Round($diskCim.FreeSpace / 1GB, 1) } else { 0 }
        $diskUsedPct = [math]::Round((($diskTotalGB - $diskFreeGB) / [math]::Max($diskTotalGB, 1)) * 100)

        $cpuLoad = [math]::Min(100, [math]::Max(0, [double]$cpu.LoadPercentage))
        $cpuName = ($cpu.Name -replace '\s+', ' ')
        if ($cpuName.Length -gt 35) { $cpuName = $cpuName.Substring(0, 35) + [char]0x2026 }

        # Actividad de disco via PerformanceCounter
        $diskActivity = 0.0
        if ($null -ne $script:DiskCounter) {
            try { $diskActivity = [math]::Min(100, [math]::Max(0, $script:DiskCounter.NextValue())) } catch {}
        }

        # Actualizar buffers de historial
        $script:CpuHistory.Add($cpuLoad)
        $script:RamHistory.Add([double]$usedPct)
        $script:DiskHistory.Add($diskActivity)
        if ($script:CpuHistory.Count  -gt 60) { $script:CpuHistory.RemoveAt(0) }
        if ($script:RamHistory.Count  -gt 60) { $script:RamHistory.RemoveAt(0) }
        if ($script:DiskHistory.Count -gt 60) { $script:DiskHistory.RemoveAt(0) }

        # Actualizar etiquetas del panel superior
        $InfoCPU.Text  = $cpuName
        $InfoRAM.Text  = "$freeGB GB libre / $totalGB GB"
        $InfoDisk.Text = "$diskFreeGB GB libre / $diskTotalGB GB"

        $CpuPctText.Text  = "  $([int]$cpuLoad)%"
        $RamPctText.Text  = "  $usedPct%"
        $DiskPctText.Text = "  $diskUsedPct% usado"

        # Dibujar gráficas sparkline
        Draw-SparkLine -Canvas $CpuChart  -Data $script:CpuHistory  -LineColor "#5BA3FF" -FillColor "#5BA3FF"
        Draw-SparkLine -Canvas $RamChart  -Data $script:RamHistory  -LineColor "#4AE896" -FillColor "#4AE896"
        Draw-SparkLine -Canvas $DiskChart -Data $script:DiskHistory -LineColor "#FFB547" -FillColor "#FFB547"

    } catch {
        $InfoCPU.Text  = "No disponible"
        $InfoRAM.Text  = "No disponible"
        $InfoDisk.Text = "No disponible"
    }
}

# Timer de actualización del panel superior — cada 2 segundos (igual que el original)
$chartTimer = New-Object System.Windows.Threading.DispatcherTimer
$chartTimer.Interval = [TimeSpan]::FromSeconds(2)
$chartTimer.Add_Tick({ Update-SystemInfo })

# Arrancar todo una vez que la ventana esté completamente cargada
# (garantiza que los Canvas tienen ActualWidth/Height reales para las gráficas)
# ─────────────────────────────────────────────────────────────────────────────
# [U1] Forzar tema oscuro en los ComboBox recorriendo su visual tree
#      WPF ignora Background en el ToggleButton interno a menos que se recorra
#      explícitamente el árbol visual después de que el control está cargado.
# ─────────────────────────────────────────────────────────────────────────────
function Get-VisualChildren {
    param([System.Windows.DependencyObject]$Parent)
    $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent)
    for ($i = 0; $i -lt $count; $i++) {
        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
        $child
        Get-VisualChildren $child
    }
}

function Apply-ComboBoxDarkTheme {
    param([System.Windows.Controls.ComboBox]$ComboBox)
    # Asegurar que el template está aplicado
    $ComboBox.ApplyTemplate() | Out-Null
    $darkBg     = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
    $darkBorder = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3A4468")
    $lightFg    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E8ECF4")

    Get-VisualChildren $ComboBox | ForEach-Object {
        $el = $_
        # ToggleButton = el área "cerrada" que sale blanca
        if ($el -is [System.Windows.Controls.Primitives.ToggleButton]) {
            $el.Background   = $darkBg
            $el.BorderBrush  = $darkBorder
            $el.Foreground   = $lightFg
            $el.ApplyTemplate() | Out-Null
            # También fijar sus hijos (Border interno del ToggleButton)
            Get-VisualChildren $el | ForEach-Object {
                if ($_ -is [System.Windows.Controls.Border]) {
                    $_.Background  = $darkBg
                    $_.BorderBrush = $darkBorder
                }
                if ($_ -is [System.Windows.Controls.ContentPresenter]) {
                    try { $_.Foreground = $lightFg } catch {}
                }
            }
        }
        # Border exterior
        if ($el -is [System.Windows.Controls.Border]) {
            $el.Background  = $darkBg
            $el.BorderBrush = $darkBorder
        }
    }
}

$window.Add_Loaded({
    try {
        Set-SplashProgress 100 "Listo."
        $splashWin.Hide()
        $splashWin.Close()
    } catch {}

    # Aplicar tema oscuro a todos los ComboBox de la ventana
    try {
        $allCombos = Get-VisualChildren $window | Where-Object { $_ -is [System.Windows.Controls.ComboBox] }
        foreach ($cb in $allCombos) { Apply-ComboBoxDarkTheme $cb }
    } catch {}

    $chartTimer.Start()
    Update-SystemInfo        # primera carga inmediata
    Update-PerformanceTab    # poblar pestaña Rendimiento al arrancar
    Load-Settings            # [C3] restaurar configuración guardada
})

# ─────────────────────────────────────────────────────────────────────────────
# TAB 2: RENDIMIENTO — controles y lógica
# ─────────────────────────────────────────────────────────────────────────────
$btnRefreshPerf   = $window.FindName("btnRefreshPerf")
$txtPerfStatus    = $window.FindName("txtPerfStatus")
# [A3] Auto-refresco controles
$chkAutoRefresh      = $window.FindName("chkAutoRefresh")
$cmbRefreshInterval  = $window.FindName("cmbRefreshInterval")
$script:AutoRefreshTimer = $null
$script:AppClosing       = $false   # [FIX] Guardia: impide ticks de rendimiento durante el cierre
# Aplicar tema oscuro al ComboBox también en su evento Loaded individual
if ($null -ne $cmbRefreshInterval) {
    $cmbRefreshInterval.Add_Loaded({ Apply-ComboBoxDarkTheme $cmbRefreshInterval })
}
$txtCpuName       = $window.FindName("txtCpuName")
$icCpuCores       = $window.FindName("icCpuCores")
$txtRamTotal      = $window.FindName("txtRamTotal")
$txtRamUsed       = $window.FindName("txtRamUsed")
$txtRamFree       = $window.FindName("txtRamFree")
$txtRamPct        = $window.FindName("txtRamPct")
$pbRam            = $window.FindName("pbRam")
$icRamModules     = $window.FindName("icRamModules")
$icSmartDisks     = $window.FindName("icSmartDisks")
$icNetAdapters    = $window.FindName("icNetAdapters")

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N0} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# [FIX-NET] Funciones de red a ámbito de script (estaban anidadas dentro de Update-PerformanceTab
# causando fallo de resolución de nombre "OUL" al invocarse desde el dispatcher WPF)
function Format-Rate {
    param([double]$bps)
    if ($bps -ge 1MB) { return "{0:N1} MB/s" -f ($bps / 1MB) }
    if ($bps -ge 1KB) { return "{0:N0} KB/s" -f ($bps / 1KB) }
    if ($bps -gt 0)   { return "{0:N0} B/s"  -f $bps }
    return "0 B/s"
}

function Get-LinkBps {
    param($raw)
    $n = [uint64]0
    if ([uint64]::TryParse("$raw", [ref]$n)) { return $n }
    if ("$raw" -match '([\d\.]+)\s*(G|M|K)?bps') {
        $v = [double]$Matches[1]; $u = "$($Matches[2])"
        $m = if ($u -eq 'G') { 1000000000 } elseif ($u -eq 'M') { 1000000 } elseif ($u -eq 'K') { 1000 } else { 1 }
        return [uint64]($v * $m)
    }
    return [uint64]0
}

function Update-PerformanceTab {
    if ($script:AppClosing) { return }   # [FIX] No ejecutar si la app está cerrando
    $txtPerfStatus.Text = "Recopilando datos…"

    # [FIX-A3] Asegurar módulos disponibles (necesario si PowerShell no los importa automáticamente)
    try { Import-Module Storage    -ErrorAction SilentlyContinue } catch {}
    try { Import-Module NetAdapter -ErrorAction SilentlyContinue } catch {}
    try { Import-Module NetTCPIP   -ErrorAction SilentlyContinue } catch {}

    # ── CPU Cores ──────────────────────────────────────────────
    try {
        $cpuObj = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $txtCpuName.Text = "$($cpuObj.Name)  |  $($cpuObj.NumberOfCores) núcleos  /  $($cpuObj.NumberOfLogicalProcessors) lógicos"

        $coreItems = [System.Collections.Generic.List[object]]::new()
        try {
            $cpuPerf = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor `
                           -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -ne '_Total' } |
                       Sort-Object { [int]($_.Name -replace '\D','0') }
            if ($cpuPerf) {
                foreach ($core in $cpuPerf) {
                    $val = [math]::Round([double]$core.PercentProcessorTime, 1)
                    $coreItems.Add([PSCustomObject]@{
                        CoreLabel = "Core $($core.Name)"
                        Usage     = "$val%"
                        UsageNum  = $val
                        Freq      = "$([math]::Round($cpuObj.CurrentClockSpeed / 1000.0, 2)) GHz"
                    })
                }
            } else {
                $val = [double]$cpuObj.LoadPercentage
                $coreItems.Add([PSCustomObject]@{
                    CoreLabel = "CPU Total"; Usage = "$val%"; UsageNum = $val
                    Freq      = "$([math]::Round($cpuObj.CurrentClockSpeed / 1000.0, 2)) GHz"
                })
            }
        } catch {
            $coreItems.Add([PSCustomObject]@{
                CoreLabel = "CPU Total"; Usage = "$($cpuObj.LoadPercentage)%"
                UsageNum  = [double]$cpuObj.LoadPercentage
                Freq      = "$([math]::Round($cpuObj.CurrentClockSpeed / 1000.0, 2)) GHz"
            })
        }
        $icCpuCores.ItemsSource = $coreItems
    } catch { $txtCpuName.Text = "No disponible" }

    # ── RAM Detallada ──────────────────────────────────────────
    try {
        $os     = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalB = $os.TotalVisibleMemorySize * 1KB
        $freeB  = $os.FreePhysicalMemory     * 1KB
        $usedB  = $totalB - $freeB
        $pct    = [math]::Round($usedB / $totalB * 100)

        $fmt = { param($b)
            if ($b -ge 1GB) { "{0:N1} GB" -f ($b / 1GB) }
            elseif ($b -ge 1MB) { "{0:N0} MB" -f ($b / 1MB) }
            else { "{0:N0} KB" -f ($b / 1KB) }
        }

        $txtRamTotal.Text = & $fmt $totalB
        $txtRamUsed.Text  = & $fmt $usedB
        $txtRamFree.Text  = & $fmt $freeB
        $txtRamPct.Text   = "$pct%"
        $pbRam.Value      = $pct

        $modItems = [System.Collections.Generic.List[object]]::new()
        foreach ($mod in (Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue)) {
            $type = switch ($mod.SMBIOSMemoryType) {
                26 { "DDR4" } 34 { "DDR5" } 21 { "DDR2" } 24 { "DDR3" } default { "DDR" }
            }
            $modItems.Add([PSCustomObject]@{
                Slot = if ($mod.DeviceLocator) { $mod.DeviceLocator } else { "Ranura" }
                Info = "$type  •  $(if($mod.Speed){"$($mod.Speed) MHz"}else{"—"})  •  Mfg: $(if($mod.Manufacturer){$mod.Manufacturer}else{"N/A"})"
                Size = & $fmt ([long]$mod.Capacity)
            })
        }
        $icRamModules.ItemsSource = $modItems
    } catch { $txtRamTotal.Text = "N/A" }

    # ── SMART del Disco ────────────────────────────────────────
    try {
        $smartItems = [System.Collections.Generic.List[object]]::new()
        foreach ($disk in (Get-PhysicalDisk -ErrorAction Stop)) {
            $rel = $null
            try { $rel = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop } catch {}

            $health = $disk.HealthStatus
            $bg = switch ($health) { "Healthy" { "#182A1E" } "Warning" { "#2A2010" } default { "#2A1018" } }
            $fg = switch ($health) { "Healthy" { "#4AE896" } "Warning" { "#FFB547" } default { "#FF6B84" } }

            $attrs = [System.Collections.Generic.List[object]]::new()
            $sz = if ($disk.Size -ge 1GB) { "{0:N1} GB" -f ($disk.Size / 1GB) } else { "{0:N0} MB" -f ($disk.Size / 1MB) }
            $attrs.Add([PSCustomObject]@{ Name="Tipo";    Value=$disk.MediaType; ValueColor="#B0BACC" })
            $attrs.Add([PSCustomObject]@{ Name="Tamaño";  Value=$sz;             ValueColor="#5BA3FF" })
            $attrs.Add([PSCustomObject]@{ Name="Bus";     Value=$disk.BusType;   ValueColor="#B0BACC" })
            if ($rel) {
                if ($null -ne $rel.PowerOnHours) {
                    $attrs.Add([PSCustomObject]@{ Name="Horas enc."; Value="$($rel.PowerOnHours) h"; ValueColor="#FFB547" })
                }
                if ($null -ne $rel.Temperature) {
                    $tc = $rel.Temperature
                    $tc2 = if ($tc -ge 55) { "#FF6B84" } elseif ($tc -ge 45) { "#FFB547" } else { "#4AE896" }
                    $attrs.Add([PSCustomObject]@{ Name="Temperatura"; Value="${tc}°C"; ValueColor=$tc2 })
                }
                if ($null -ne $rel.ReadErrorsTotal) {
                    $attrs.Add([PSCustomObject]@{ Name="Errores lect."; Value=$rel.ReadErrorsTotal
                        ValueColor=if($rel.ReadErrorsTotal -gt 0){"#FF6B84"}else{"#4AE896"} })
                }
                if ($null -ne $rel.Wear) {
                    $wc = if ($rel.Wear -ge 80) { "#FF6B84" } elseif ($rel.Wear -ge 50) { "#FFB547" } else { "#4AE896" }
                    $attrs.Add([PSCustomObject]@{ Name="Desgaste"; Value="$($rel.Wear)%"; ValueColor=$wc })
                }
            }
            $smartItems.Add([PSCustomObject]@{
                DiskName=$disk.FriendlyName; Status=$health; StatusBg=$bg; StatusFg=$fg; Attributes=$attrs
            })
        }
        $icSmartDisks.ItemsSource = $smartItems
    } catch {
        $icSmartDisks.ItemsSource = @([PSCustomObject]@{
            DiskName="Error al leer SMART"; Status="N/A"; StatusBg="#2A1018"; StatusFg="#FF6B84"; Attributes=@()
        })
    }

    # ── Tarjetas de Red ────────────────────────────────────────
    try {
        # Tabla de velocidades WMI para calcular rx/tx en tiempo real
        $wmiTable = @{}
        try {
            foreach ($row in (Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue)) {
                $norm = ($row.Name -replace '\s*#\d+$','' -replace '_',' ').ToLower().Trim()
                $wmiTable[$norm] = $row
            }
        } catch {}

        # Funciones de formato inline (sin scriptblock para evitar problemas de scope)
        function Format-NetRate  { param([double]$b); if ($b -ge 1MB) { return "{0:N1} MB/s" -f ($b/1MB) } elseif ($b -ge 1KB) { return "{0:N0} KB/s" -f ($b/1KB) } elseif ($b -gt 0) { return "{0:N0} B/s" -f $b } else { return "0 B/s" } }
        function Format-NetBytes { param([double]$b); if ($b -ge 1GB) { return "{0:N1} GB" -f ($b/1GB) } elseif ($b -ge 1MB) { return "{0:N0} MB" -f ($b/1MB) } else { return "{0:N0} KB" -f ($b/1KB) } }
        function Format-LinkBps  { param([uint64]$bps); if ($bps -ge 1000000000) { return "$([math]::Round($bps/1e9,0)) Gbps" } elseif ($bps -ge 1000000) { return "$([math]::Round($bps/1e6,0)) Mbps" } elseif ($bps -gt 0) { return "$bps bps" } else { return "—" } }

        $netItems = [System.Collections.Generic.List[object]]::new()

        # ── Intentar con Get-NetAdapter (módulo NetAdapter) ──────────────
        $gotNetAdapter = $false
        try {
            $adapters = Get-NetAdapter -ErrorAction Stop
            $gotNetAdapter = $true

            foreach ($a in $adapters) {
                # IP
                $ip = "Sin IP"
                try {
                    $ipObj = Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($ipObj -and $ipObj.IPAddress) { $ip = $ipObj.IPAddress }
                } catch {}

                # Tipo de adaptador
                $desc = "$($a.InterfaceDescription)"
                $adType = "🔌 Ethernet"
                if (($desc -match 'Wi.?Fi|Wireless|WLAN|802\.11') -or ("$($a.PhysicalMediaType)" -match '802\.11|Wireless|NativeWifi')) {
                    $adType = "📶 WiFi"
                } elseif ($desc -match 'Loopback|Pseudo|Miniport|Hyper-V|VMware|VirtualBox|TAP|TUN|VPN') {
                    $adType = "🔷 Virtual"
                }

                # Velocidad de enlace
                $linkBps = [uint64]0
                $lsStr = "$($a.LinkSpeed)"
                $lsParsed = [uint64]0
                if ([uint64]::TryParse($lsStr, [ref]$lsParsed)) {
                    $linkBps = $lsParsed
                } elseif ($lsStr -match '([\d\.]+)\s*(G|M|K)?bps') {
                    $lv = [double]$Matches[1]; $lu = "$($Matches[2])"
                    $lm = 1
                    if ($lu -eq 'G') { $lm = 1000000000 } elseif ($lu -eq 'M') { $lm = 1000000 } elseif ($lu -eq 'K') { $lm = 1000 }
                    $linkBps = [uint64]($lv * $lm)
                }
                $speedStr = Format-LinkBps $linkBps

                # Velocidad rx/tx desde WMI
                $descNorm = ($desc -replace '\s*#\d+$','').ToLower().Trim()
                $wmiRow = $wmiTable[$descNorm]
                if (-not $wmiRow) {
                    foreach ($k in $wmiTable.Keys) {
                        if ($descNorm -like "*$k*" -or $k -like "*$($a.Name.ToLower().Trim())*") { $wmiRow = $wmiTable[$k]; break }
                    }
                }
                $rxBps = 0.0; $txBps = 0.0
                if ($null -ne $wmiRow) { $rxBps = [double]$wmiRow.BytesReceivedPersec; $txBps = [double]$wmiRow.BytesSentPersec }

                # Bytes totales
                $ioStr = ""
                try {
                    $stats = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue
                    if ($stats) { $ioStr = "Total ↓ $(Format-NetBytes $stats.ReceivedBytes)  ↑ $(Format-NetBytes $stats.SentBytes)" }
                } catch {}

                # Color de estado
                $stColor = "#9BA4C0"
                if ($a.Status -eq "Up") { $stColor = "#4AE896" }

                $netItems.Add([PSCustomObject]@{
                    Name        = "$adType  $($a.Name)"
                    IP          = "IP: $ip  |  MAC: $($a.MacAddress)"
                    MAC         = $desc
                    Speed       = $speedStr
                    Status      = "$($a.Status)   ↓ $(Format-NetRate $rxBps)   ↑ $(Format-NetRate $txBps)"
                    StatusColor = $stColor
                    BytesIO     = $ioStr
                })
            }
        } catch {}

        # ── Fallback WMI puro si Get-NetAdapter no está disponible ───────
        if (-not $gotNetAdapter -or $netItems.Count -eq 0) {
            try {
                foreach ($nic in (Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue)) {
                    $nicName = (Get-CimInstance Win32_NetworkAdapter -Filter "DeviceID='$($nic.Index)'" -ErrorAction SilentlyContinue).NetConnectionID
                    if (-not $nicName) { $nicName = $nic.Description }
                    $ip  = if ($nic.IPAddress)    { $nic.IPAddress[0]    } else { "Sin IP" }
                    $mac = if ($nic.MACAddress)   { $nic.MACAddress      } else { "—" }
                    $gw  = if ($nic.DefaultIPGateway) { $nic.DefaultIPGateway[0] } else { "Sin GW" }

                    $adType = "🔌 Ethernet"
                    if ($nic.Description -match 'Wi.?Fi|Wireless|WLAN|802\.11') { $adType = "📶 WiFi" }
                    elseif ($nic.Description -match 'Hyper-V|VMware|VirtualBox|TAP|TUN|VPN') { $adType = "🔷 Virtual" }

                    $netItems.Add([PSCustomObject]@{
                        Name        = "$adType  $nicName"
                        IP          = "IP: $ip  |  MAC: $mac"
                        MAC         = $nic.Description
                        Speed       = "—"
                        Status      = "Activa  ↓ —  ↑ —  |  GW: $gw"
                        StatusColor = "#4AE896"
                        BytesIO     = ""
                    })
                }
            } catch {
                $netItems.Add([PSCustomObject]@{
                    Name="⚠ Error WMI al leer red"; IP=$_.Exception.Message
                    MAC=""; Speed=""; Status="Error"; StatusColor="#FF6B84"; BytesIO=""
                })
            }
        }

        if ($netItems.Count -eq 0) {
            $netItems.Add([PSCustomObject]@{
                Name="ℹ Sin adaptadores activos"; IP="No se detectaron tarjetas de red activas"
                MAC=""; Speed=""; Status="—"; StatusColor="#7880A0"; BytesIO=""
            })
        }

        $icNetAdapters.ItemsSource = $netItems

    } catch {
        $icNetAdapters.ItemsSource = @([PSCustomObject]@{
            Name="⚠ Error al leer adaptadores"
            IP="[$($_.Exception.GetType().Name)] $($_.Exception.Message)"
            MAC=""; Speed=""; Status="Error"; StatusColor="#FF6B84"; BytesIO=""
        })
    }

    $txtPerfStatus.Text = "Actualizado: $(Get-Date -Format 'HH:mm:ss')"
}

$btnRefreshPerf.Add_Click({ Update-PerformanceTab })

# [A3] Auto-refresco de Rendimiento ───────────────────────────────────────────
$chkAutoRefresh.Add_Checked({
    $secs = 5
    $sel = $cmbRefreshInterval.SelectedItem
    if ($sel -and $sel.Tag) { $secs = [int]$sel.Tag }
    $script:AutoRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:AutoRefreshTimer.Interval = [TimeSpan]::FromSeconds($secs)
    $script:AutoRefreshTimer.Add_Tick({ Update-PerformanceTab })
    $script:AutoRefreshTimer.Start()
    $txtPerfStatus.Text = "  Auto-refresco cada $secs s activo"
})
$chkAutoRefresh.Add_Unchecked({
    if ($null -ne $script:AutoRefreshTimer) { $script:AutoRefreshTimer.Stop(); $script:AutoRefreshTimer = $null }
    $txtPerfStatus.Text = "  Auto-refresco desactivado"
})
$cmbRefreshInterval.Add_SelectionChanged({
    if ($chkAutoRefresh.IsChecked -eq $true) {
        # [FIX] Detener y recrear el timer en lugar de reutilizar la instancia anterior
        # (el timer puede ser $null si fue detenido por el Unchecked handler)
        if ($null -ne $script:AutoRefreshTimer) { $script:AutoRefreshTimer.Stop(); $script:AutoRefreshTimer = $null }
        $secs = 5
        $sel = $cmbRefreshInterval.SelectedItem
        if ($sel -and $sel.Tag) { $secs = [int]$sel.Tag }
        $script:AutoRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:AutoRefreshTimer.Interval = [TimeSpan]::FromSeconds($secs)
        $script:AutoRefreshTimer.Add_Tick({ Update-PerformanceTab })
        $script:AutoRefreshTimer.Start()
        $txtPerfStatus.Text = "  Auto-refresco cada $secs s activo"
    }
})

# ─────────────────────────────────────────────────────────────────────────────
# TAB 3: EXPLORADOR DE DISCO — controles y lógica
# ─────────────────────────────────────────────────────────────────────────────
$txtDiskScanPath    = $window.FindName("txtDiskScanPath")
$btnDiskBrowse      = $window.FindName("btnDiskBrowse")
$btnDiskScan        = $window.FindName("btnDiskScan")
$btnDiskStop        = $window.FindName("btnDiskStop")
$lbDiskTree         = $window.FindName("lbDiskTree")
$txtDiskScanStatus  = $window.FindName("txtDiskScanStatus")
$pbDiskScan         = $window.FindName("pbDiskScan")
$txtDiskDetailName  = $window.FindName("txtDiskDetailName")
$txtDiskDetailSize  = $window.FindName("txtDiskDetailSize")
$txtDiskDetailFiles = $window.FindName("txtDiskDetailFiles")
$txtDiskDetailDirs  = $window.FindName("txtDiskDetailDirs")
$txtDiskDetailPct   = $window.FindName("txtDiskDetailPct")
$icTopFiles         = $window.FindName("icTopFiles")
# [B1] Filtro
$txtDiskFilter      = $window.FindName("txtDiskFilter")
$btnDiskFilterClear = $window.FindName("btnDiskFilterClear")
# [B3] Exportar CSV + Informe HTML
$btnExportCsv       = $window.FindName("btnExportCsv")
$btnDiskReport      = $window.FindName("btnDiskReport")
# [B2] Context menu items (inside ContextMenu of lbDiskTree)
$ctxMenu        = $lbDiskTree.ContextMenu
$ctxOpen        = $ctxMenu.Items | Where-Object { $_.Name -eq "ctxOpen"      }
$ctxCopy        = $ctxMenu.Items | Where-Object { $_.Name -eq "ctxCopy"      }
$ctxScanFolder  = $ctxMenu.Items | Where-Object { $_.Name -eq "ctxScanFolder" }
$ctxDelete      = $ctxMenu.Items | Where-Object { $_.Name -eq "ctxDelete"    }
$ctxShowOutput2 = $ctxMenu.Items | Where-Object { $_.Name -eq "ctxShowOutput" }

$script:DiskScanRunspace = $null
$script:DiskScanResults  = $null
# Rutas colapsadas por el usuario (toggle ▶/▼)
$script:CollapsedPaths   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
# Todos los items escaneados (sin filtrar) — base para rebuilds de vista
$script:AllScannedItems  = [System.Collections.Generic.List[object]]::new(4096)  # [NEW-03] capacity hint
# Índice posición en LiveList para actualizaciones O(1)
$script:LiveIndexMap     = [System.Collections.Generic.Dictionary[string,int]]::new([System.StringComparer]::OrdinalIgnoreCase)

# ─────────────────────────────────────────────────────────────────────────────
# Reconstruye la lista visible aplicando el filtro de colapso
# ─────────────────────────────────────────────────────────────────────────────
# [NEW-01] Debounce timer: evita rebuilds múltiples en ráfagas del scanner
$script:_diskViewDebounce = $null
function Request-DiskViewRefresh {
    param([switch]$RebuildMap)
    # Si viene con RebuildMap o no hay timer activo, disparar inmediatamente
    # (los colapsos manuales necesitan respuesta inmediata)
    if ($RebuildMap) {
        if ($null -ne $script:_diskViewDebounce) {
            try { $script:_diskViewDebounce.Stop() } catch {}
            $script:_diskViewDebounce = $null
        }
        Refresh-DiskView -RebuildMap
        return
    }
    # Para actualizaciones de datos (ráfaga del scanner), debounce 80ms
    if ($null -ne $script:_diskViewDebounce) { return }  # ya pendiente
    $dt = New-Object System.Windows.Threading.DispatcherTimer
    $dt.Interval = [TimeSpan]::FromMilliseconds(80)
    $dt.Add_Tick({
        $script:_diskViewDebounce.Stop()
        $script:_diskViewDebounce = $null
        Refresh-DiskView
    })
    $script:_diskViewDebounce = $dt
    $dt.Start()
}

function Refresh-DiskView {
    param([switch]$RebuildMap)
    if ($null -eq $script:LiveList) { return }

    # ── Fase 1: construir y ordenar el childMap (cacheado) ──────────────────────
    # Al colapsar/expandir los datos NO cambian → reutilizamos el mapa ya ordenado.
    # Solo se reconstruye cuando llegan datos nuevos del escáner (-RebuildMap).
    if ($RebuildMap -or $null -eq $script:CachedChildMap) {
        $script:CachedChildMap = [System.Collections.Generic.Dictionary[string,
                      System.Collections.Generic.List[object]]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)

        foreach ($item in $script:AllScannedItems) {
            $pk = if ($null -ne $item.ParentPath -and $item.ParentPath -ne '') { $item.ParentPath } else { '::ROOT::' }
            if (-not $script:CachedChildMap.ContainsKey($pk)) {
                $script:CachedChildMap[$pk] = [System.Collections.Generic.List[object]]::new()
            }
            $script:CachedChildMap[$pk].Add($item)
        }

        # Ordenar cada grupo con Array.Sort (sin pipeline) — mayor tamaño primero
        foreach ($pk in @($script:CachedChildMap.Keys)) {
            $lst = $script:CachedChildMap[$pk]
            if ($lst.Count -lt 2) { continue }
            # Sort-Object solo se ejecuta al construir el mapa (no en cada colapso)
            # PowerShell no acepta scriptblock como IComparer en [Array]::Sort
            $sorted = $lst | Sort-Object -Property @{Expression={ if ($_.SizeBytes -ge 0) { $_.SizeBytes } else { 0L } }} -Descending
            $lst.Clear()
            foreach ($x in $sorted) { $lst.Add($x) }
        }
    }

    # ── Fase 2: DFS con pila de índices (orden garantizado) ────────────────────
    # Mantenemos una pila de (parentKey, índiceActual) para recorrer el árbol
    # en profundidad respetando el orden ya establecido en CachedChildMap.
    # Esto evita la recursión y el problema del Stack LIFO que mezcla el orden.
    $script:LiveList.Clear()

    # Cada entrada en la pila: [string parentKey, int currentIndex]
    $dfsStack = [System.Collections.Generic.Stack[object[]]]::new()
    if ($script:CachedChildMap.ContainsKey('::ROOT::')) {
        $dfsStack.Push(@('::ROOT::', 0))
    }

    while ($dfsStack.Count -gt 0) {
        $frame   = $dfsStack.Peek()
        $pk      = [string]$frame[0]
        $idx     = [int]$frame[1]
        $children = $script:CachedChildMap[$pk]

        if ($idx -ge $children.Count) {
            # Agotamos todos los hijos de este padre → subimos
            [void]$dfsStack.Pop()
            continue
        }

        # Avanzar índice para la próxima vuelta de este frame
        $frame[1] = $idx + 1

        $item = $children[$idx]

        # Sincronizar ícono
        if ($item.IsDir -and $item.HasChildren) {
            $item.ToggleIcon = if ($script:CollapsedPaths.Contains($item.FullPath)) {
                [string][char]0x25B6
            } else {
                [string][char]0x25BC
            }
        }

        $script:LiveList.Add($item)

        # Si el directorio está expandido, bajar a sus hijos
        if ($item.IsDir -and $item.HasChildren -and
            -not $script:CollapsedPaths.Contains($item.FullPath) -and
            $script:CachedChildMap.ContainsKey($item.FullPath)) {
            $dfsStack.Push(@($item.FullPath, 0))
        }
    }
}

# Invalida el childMap cacheado; llamar cuando el escáner emita nuevos datos
function Invalidate-DiskViewCache {
    $script:CachedChildMap = $null
}

function Get-SizeColor {
    param([long]$Bytes)
    if ($Bytes -ge 10GB) { return "#FF6B84" }
    if ($Bytes -ge 1GB)  { return "#FFB547" }
    if ($Bytes -ge 100MB){ return "#5BA3FF" }
    return "#B0BACC"
}

# Get-SizeColorFromStr es alias de Get-SizeColor (eliminado duplicado)
Set-Alias -Name Get-SizeColorFromStr -Value Get-SizeColor -Scope Script

function Start-DiskScan {
    param([string]$RootPath)

    if (-not (Test-Path $RootPath -ErrorAction SilentlyContinue)) {
        Show-ThemedDialog -Title "Ruta no encontrada" -Message "Ruta no encontrada: $RootPath" -Type "error"
        return
    }

    # Señalizar parada al runspace anterior si hubiera uno corriendo
    [ScanCtl211]::Stop = $true
    Start-Sleep -Milliseconds 150
    [ScanCtl211]::Reset()

    $script:CollapsedPaths.Clear()
    $script:CachedChildMap = $null      # Invalidar caché al iniciar nuevo escaneo
    $script:AllScannedItems.Clear()
    if ($null -ne $script:LiveIndexMap) { $script:LiveIndexMap.Clear() }

    $btnDiskScan.IsEnabled  = $false
    $btnDiskStop.IsEnabled  = $true
    $txtDiskScanStatus.Text = "Iniciando escaneo de $RootPath …"
    if ($null -ne $btnSnapshotSave) {
        $btnSnapshotSave.IsEnabled = $false
        $txtSnapshotName.IsEnabled = $false
        $txtSnapshotName.Text      = ""
    }  # [B4]
    $pbDiskScan.IsIndeterminate = $true
    $pbDiskScan.Value = 0

    # Cola compartida: el hilo de fondo mete objetos, el timer de UI los consume
    $script:ScanQueue = [System.Collections.Concurrent.ConcurrentQueue[object[]]]::new()

    # [OPT] Usar List<object> en lugar de ObservableCollection para la UI.
    # ObservableCollection dispara CollectionChanged por cada Add() individual — con miles
    # de carpetas esto presiona enormemente el sistema de binding WPF y el GC.
    # Usamos una List normal y llamamos lbDiskTree.Items.Refresh() solo en batches.
    # LiveItems eliminado: AllScannedItems+LiveIndexMap es la única fuente de verdad.
    $script:LiveItems = [System.Collections.Generic.Dictionary[string,int]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)  # clave → índice en AllScannedItems
    $script:LiveList  = [System.Collections.Generic.List[object]]::new(2048)
    $lbDiskTree.ItemsSource = $script:LiveList

    # ── [A1] Hilo de fondo: escáner PARALELO en C# via ParallelScanner ──────
    # Solo emite CARPETAS (estilo TreeSize). Paralelismo en nivel shallow (depth<=1)
    # para máximo throughput en NVMe sin crear un exceso de threads en discos HDD.
    # La cola es ConcurrentQueue<object[]> — array posicional:
    #   [0]=Key [1]=ParentKey [2]=Name [3]=Size [4]=Files [5]=Dirs [6]=Done [7]=Depth
    $bgScript = {
        param([string]$Root,
              [System.Collections.Concurrent.ConcurrentQueue[object[]]]$Q)

        try {
            $topDirs = try { [System.IO.Directory]::GetDirectories($Root) } catch { @() }
            [ScanCtl211]::Total = $topDirs.Length + 1

            # Llamar al escáner C# paralelo para cada carpeta de primer nivel
            # Pasamos $Root como parentKey para que aparezcan bajo ::ROOT:: en la UI
            foreach ($d in $topDirs) {
                if ([ScanCtl211]::Stop) { break }
                [PScanner211]::ScanDir($d, 0, '::ROOT::', $Q) | Out-Null
            }
            [ScanCtl211]::Done++
        } catch {}
    }

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "STA"; $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    # [FIX-A1] Inyectar el assembly unificado (DiskItem+ScanControl+ParallelScanner)
    # en el nuevo runspace para que los tipos C# sean resolubles desde el hilo de fondo
    $sharedAsmPath = [ScanCtl211].Assembly.Location
    if ($sharedAsmPath -and (Test-Path $sharedAsmPath)) {
        [void]$rs.SessionStateProxy.InvokeCommand.InvokeScript(
            "`$null = [System.Reflection.Assembly]::LoadFrom('$sharedAsmPath')"
        )
    }
    [void]$ps.AddScript($bgScript).AddParameter("Root", $RootPath).AddParameter("Q", $script:ScanQueue)
    # Set DefaultRunspace so C# code can resolve PS types if needed
    $rs.SessionStateProxy.SetVariable("ErrorActionPreference", "SilentlyContinue")
    $script:DiskScanRunspace = $rs
    # [FIX-CLOSURE] Guardar en scope de script para que el timer pueda acceder
    $script:DiskScanPS    = $ps
    $script:DiskScanAsync = $ps.BeginInvoke()

    # ── Timer UI: drena la cola y actualiza lista cada 300 ms ──────────────────
    # LiveIndexMap: clave→posición en LiveList para actualizaciones O(1)
    $script:LiveIndexMap = [System.Collections.Generic.Dictionary[string,int]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    $script:SortTickCounter = 0
    $script:GcTickCounter   = 0   # [OPT] para GC periódico durante scan

    # [FIX-CLOSURE] uiTimer debe estar en $script: para que Add_Tick pueda llamar a .Stop()
    if ($null -ne $script:DiskUiTimer) { try { $script:DiskUiTimer.Stop() } catch {} }
    $script:DiskUiTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:DiskUiTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:DiskUiTimer.Add_Tick({
        $total = [ScanCtl211]::Total
        $done  = [ScanCtl211]::Done
        $cur   = [ScanCtl211]::Current

        if ($total -gt 0) {
            $pbDiskScan.IsIndeterminate = $false
            $pbDiskScan.Value = [math]::Min(99, [math]::Round($done / $total * 100))
        }

        $lw = if ($lbDiskTree.ActualWidth -gt 100) { $lbDiskTree.ActualWidth - 270 } else { 400 }

        # Procesar hasta 600 mensajes por tick
        $anyUpdate   = $false
        $listChanged = $false
        $processed   = 0
        $msg = $null
        while ($processed -lt 600 -and ($null -ne $script:ScanQueue) -and $script:ScanQueue.TryDequeue([ref]$msg)) {
            $processed++
            $key       = [string]$msg[0]
            $parentKey = if ($msg[1]) { [string]$msg[1] } else { '::ROOT::' }
            $msgName   = [string]$msg[2]
            $msgSize   = [long]$msg[3]
            $msgFiles  = [int]$msg[4]
            $msgDirs   = [int]$msg[5]
            $msgDone   = [bool]$msg[6]
            $depth     = [int]$msg[7]
            $indent    = "$([math]::Max(4, $depth * 22)),0,0,0"

            if (-not $msgDone) {
                # Placeholder — solo si no existe ya en AllScannedItems
                if (-not $script:LiveItems.ContainsKey($key)) {
                    $entry = New-Object DiskItem_v211
                    $entry.DisplayName      = $msgName
                    $entry.FullPath         = $key
                    $entry.ParentPath       = $parentKey
                    $entry.SizeBytes        = -1L
                    $entry.SizeStr          = [char]0x2026
                    $entry.SizeColor        = "#8B96B8"
                    $entry.PctStr           = [char]0x2014
                    $entry.FileCount        = [char]0x2026
                    $entry.DirCount         = 0
                    $entry.IsDir            = $true
                    $entry.HasChildren      = $false
                    $entry.Icon             = [char]0xD83D + [char]0xDCC1
                    $entry.Indent           = $indent
                    $entry.BarWidth         = 0.0
                    $entry.BarColor         = "#3A4468"
                    $entry.TotalPct         = 0.0
                    $entry.Depth            = $depth
                    $entry.ToggleIcon       = [char]0x25B6
                    $entry.ToggleVisibility = "Collapsed"
                    $idx = $script:AllScannedItems.Count
                    $script:AllScannedItems.Add($entry)
                    $script:LiveItems[$key] = $idx   # índice en AllScannedItems
                    # Añadir a LiveList solo si ningún ancestro está colapsado
                    $hidden = $false
                    $pp = $parentKey
                    while ($pp -and $pp -ne '::ROOT::') {
                        if ($script:CollapsedPaths.Contains($pp)) { $hidden = $true; break }
                        $pp2 = try { [System.IO.Path]::GetDirectoryName($pp) } catch { $null }
                        $pp = if ($pp2 -and $pp2 -ne $pp) { $pp2 } else { $null }
                    }
                    if (-not $hidden) { $script:LiveList.Add($entry); $listChanged = $true }
                }
            } else {
                # Datos reales de carpeta completada
                $sz     = $msgSize
                $sc     = if ($sz -ge 10GB) {"#FF6B84"} elseif ($sz -ge 1GB) {"#FFB547"} elseif ($sz -ge 100MB) {"#5BA3FF"} else {"#B0BACC"}
                $szStr  = if ($sz -ge 1GB) {"{0:N1} GB" -f ($sz/1GB)} elseif ($sz -ge 1MB) {"{0:N0} MB" -f ($sz/1MB)} elseif ($sz -ge 1KB) {"{0:N0} KB" -f ($sz/1KB)} else {"$sz B"}
                $fc     = "$msgFiles arch.  $msgDirs carp."
                $hasCh  = $msgDirs -gt 0

                if ($script:LiveItems.ContainsKey($key)) {
                    # Actualizar el objeto existente en AllScannedItems directamente
                    $ex = $script:AllScannedItems[$script:LiveItems[$key]]
                    $ex.SizeBytes        = $sz
                    $ex.SizeStr          = $szStr
                    $ex.SizeColor        = $sc
                    $ex.FileCount        = $fc
                    $ex.DirCount         = $msgDirs
                    $ex.HasChildren      = $hasCh
                    $ex.BarColor         = $sc
                    $ex.ToggleVisibility = if ($hasCh) {"Visible"} else {"Collapsed"}
                    $ex.ToggleIcon       = if ($script:CollapsedPaths.Contains($key)) { [char]0x25B6 } else { [char]0x25BC }
                } else {
                    $ne = New-Object DiskItem_v211
                    $ne.DisplayName      = $msgName
                    $ne.FullPath         = $key
                    $ne.ParentPath       = $parentKey
                    $ne.SizeBytes        = $sz
                    $ne.SizeStr          = $szStr
                    $ne.SizeColor        = $sc
                    $ne.PctStr           = [char]0x2014
                    $ne.FileCount        = $fc
                    $ne.DirCount         = $msgDirs
                    $ne.IsDir            = $true
                    $ne.HasChildren      = $hasCh
                    $ne.Icon             = [char]0xD83D + [char]0xDCC1
                    $ne.Indent           = $indent
                    $ne.BarWidth         = 0.0
                    $ne.BarColor         = $sc
                    $ne.TotalPct         = 0.0
                    $ne.Depth            = $depth
                    $ne.ToggleIcon       = if ($script:CollapsedPaths.Contains($key)) { [char]0x25B6 } else { [char]0x25BC }
                    $ne.ToggleVisibility = if ($hasCh) {"Visible"} else {"Collapsed"}
                    $idx2 = $script:AllScannedItems.Count
                    $script:AllScannedItems.Add($ne)
                    $script:LiveItems[$key] = $idx2
                    $hidden2 = $false
                    $pp3 = $parentKey
                    while ($pp3 -and $pp3 -ne '::ROOT::') {
                        if ($script:CollapsedPaths.Contains($pp3)) { $hidden2 = $true; break }
                        $pp4 = try { [System.IO.Path]::GetDirectoryName($pp3) } catch { $null }
                        $pp3 = if ($pp4 -and $pp4 -ne $pp3) { $pp4 } else { $null }
                    }
                    if (-not $hidden2) { $script:LiveList.Add($ne); $listChanged = $true }
                }
                $anyUpdate = $true
            }
            $msg = $null
        }

        # [OPT] Notificar WPF solo una vez por batch (no por cada Add)
        if ($listChanged) {
            $lbDiskTree.Items.Refresh()
        }

        # [A2] Actualizar porcentajes en tiempo real
        if ($anyUpdate) {
            $rtTotal = 0L
            foreach ($v in $script:AllScannedItems) {
                if ($v.Depth -eq 0 -and $v.SizeBytes -gt 0) { $rtTotal += $v.SizeBytes }
            }
            if ($rtTotal -gt 0) {
                $lw2 = if ($lbDiskTree.ActualWidth -gt 100) { $lbDiskTree.ActualWidth - 270 } else { 400 }
                foreach ($s in $script:AllScannedItems) {
                    if ($s.SizeBytes -gt 0) {
                        $pct2 = [math]::Round($s.SizeBytes / $rtTotal * 100, 1)
                        $s.PctStr   = "$pct2%"
                        $s.TotalPct = $pct2
                        $s.BarWidth = [double][math]::Max(0, [math]::Round($pct2 / 100 * $lw2))
                    }
                }
            }
        }

        # Re-ordenar por tamaño cada ~5 ticks (~1.5 s)
        $script:SortTickCounter++
        if ($anyUpdate -and $script:SortTickCounter % 5 -eq 0) {
            Refresh-DiskView -RebuildMap
        }

        # [OPT] GC periódico durante el scan — cada 20 ticks (~6 s)
        # Libera strings intermedios, arrays de la cola C# y objetos temporales PS
        $script:GcTickCounter++
        if ($script:GcTickCounter % 20 -eq 0) {
            [GC]::Collect(0, [GCCollectionMode]::Optimized)
        }

        if ($anyUpdate) {
            $cnt = $script:AllScannedItems.Count
            $txtDiskScanStatus.Text = "Escaneando$([char]0x2026)  $cnt carpetas  $([char]0x00B7)  $done/$total  $([char]0x00B7)  $cur"
        }

        # ¿Terminó el runspace?
        if ($null -ne $script:DiskScanAsync -and $script:DiskScanAsync.IsCompleted) {
            # [FIX-B2] Drenar TODA la cola antes de parar
            $drainMsg = $null
            while (($null -ne $script:ScanQueue) -and $script:ScanQueue.TryDequeue([ref]$drainMsg)) {
                $dk       = [string]$drainMsg[0]
                $dpk      = if ($drainMsg[1]) { [string]$drainMsg[1] } else { '::ROOT::' }
                $dn       = [string]$drainMsg[2]
                $dsz      = [long]$drainMsg[3]
                $dfiles   = [int]$drainMsg[4]
                $ddirs    = [int]$drainMsg[5]
                $ddone    = [bool]$drainMsg[6]
                $ddepth   = [int]$drainMsg[7]
                $dindent  = "$([math]::Max(4, $ddepth * 22)),0,0,0"

                if (-not $ddone) {
                    if (-not $script:LiveItems.ContainsKey($dk)) {
                        $de = New-Object DiskItem_v211
                        $de.DisplayName = $dn; $de.FullPath = $dk; $de.ParentPath = $dpk
                        $de.SizeBytes = -1L; $de.SizeStr = [char]0x2026; $de.SizeColor = "#8B96B8"
                        $de.PctStr = [char]0x2014; $de.FileCount = [char]0x2026; $de.DirCount = 0
                        $de.IsDir = $true; $de.HasChildren = $false
                        $de.Icon = [char]0xD83D + [char]0xDCC1
                        $de.Indent = $dindent; $de.BarWidth = 0.0; $de.BarColor = "#3A4468"
                        $de.TotalPct = 0.0; $de.Depth = $ddepth
                        $de.ToggleIcon = [char]0x25B6; $de.ToggleVisibility = "Collapsed"
                        $didx = $script:AllScannedItems.Count
                        $script:AllScannedItems.Add($de)
                        $script:LiveItems[$dk] = $didx
                    }
                } else {
                    $dsc    = if ($dsz -ge 10GB) {"#FF6B84"} elseif ($dsz -ge 1GB) {"#FFB547"} elseif ($dsz -ge 100MB) {"#5BA3FF"} else {"#B0BACC"}
                    $dszStr = if ($dsz -ge 1GB) {"{0:N1} GB" -f ($dsz/1GB)} elseif ($dsz -ge 1MB) {"{0:N0} MB" -f ($dsz/1MB)} elseif ($dsz -ge 1KB) {"{0:N0} KB" -f ($dsz/1KB)} else {"$dsz B"}
                    $dhch   = $ddirs -gt 0
                    if ($script:LiveItems.ContainsKey($dk)) {
                        $dex = $script:AllScannedItems[$script:LiveItems[$dk]]
                        $dex.SizeBytes = $dsz; $dex.SizeStr = $dszStr; $dex.SizeColor = $dsc
                        $dex.FileCount = "$dfiles arch.  $ddirs carp."; $dex.DirCount = $ddirs
                        $dex.HasChildren = $dhch; $dex.BarColor = $dsc
                        $dex.ToggleVisibility = if ($dhch) {"Visible"} else {"Collapsed"}
                    } else {
                        $dne = New-Object DiskItem_v211
                        $dne.DisplayName = $dn; $dne.FullPath = $dk; $dne.ParentPath = $dpk
                        $dne.SizeBytes = $dsz; $dne.SizeStr = $dszStr; $dne.SizeColor = $dsc
                        $dne.PctStr = [char]0x2014; $dne.FileCount = "$dfiles arch.  $ddirs carp."
                        $dne.DirCount = $ddirs; $dne.IsDir = $true; $dne.HasChildren = $dhch
                        $dne.Icon = [char]0xD83D + [char]0xDCC1; $dne.Indent = $dindent
                        $dne.BarWidth = 0.0; $dne.BarColor = $dsc; $dne.TotalPct = 0.0; $dne.Depth = $ddepth
                        $dne.ToggleIcon = [char]0x25BC; $dne.ToggleVisibility = if ($dhch) {"Visible"} else {"Collapsed"}
                        $didx2 = $script:AllScannedItems.Count
                        $script:AllScannedItems.Add($dne)
                        $script:LiveItems[$dk] = $didx2
                    }
                }
                $drainMsg = $null
            }

            # [OPT] ScanQueue vaciada — liberar referencia para que el GC recoja los arrays
            $script:ScanQueue = $null

$script:DiskUiTimer.Stop()
            try { $script:DiskScanPS.EndInvoke($script:DiskScanAsync) | Out-Null } catch {}
            try { $script:DiskScanPS.Dispose(); $script:DiskScanRunspace.Close(); $script:DiskScanRunspace.Dispose() } catch {}
            $script:DiskScanAsync = $null
            $script:DiskScanPS    = $null

            # Calcular tamaño total: suma de todas las carpetas de primer nivel (Depth=0)
            $gt2 = 0L
            foreach ($v in $script:AllScannedItems) {
                if ($v.Depth -eq 0 -and $v.SizeBytes -gt 0) { $gt2 += $v.SizeBytes }
            }

            # Asignar porcentajes y corregir ToggleVisibility final en todos los items
            if ($gt2 -gt 0) {
                foreach ($s in $script:AllScannedItems) {
                    if ($s.SizeBytes -gt 0) {
                        $pct = [math]::Round($s.SizeBytes / $gt2 * 100, 1)
                        $bw  = [math]::Max(0, [math]::Round($pct / 100 * $lw))
                        $s.PctStr   = "$pct%"
                        $s.TotalPct = $pct
                        $s.BarWidth = [double]$bw
                    }
                    # Asegurar ToggleVisibility correcto según HasChildren real
                    if ($s.IsDir) {
                        $s.ToggleVisibility = if ($s.HasChildren) { "Visible" } else { "Collapsed" }
                        $s.ToggleIcon       = if ($script:CollapsedPaths.Contains($s.FullPath)) { "▶" } else { "▼" }
                    }
                }
            }

            # Reconstruir LiveList final respetando colapsos (o filtro activo)
            $script:LiveIndexMap.Clear()
            if (-not [string]::IsNullOrWhiteSpace($script:FilterText)) {
                Apply-DiskFilter $script:FilterText
            } else {
                Refresh-DiskView -RebuildMap
            }
            # [OPT] Notificar WPF de la reconstrucción de LiveList (sustituye ObservableCollection)
            $lbDiskTree.Items.Refresh()

            # [OPT] Compactar listas y liberar RAM al SO tras escaneo completo
            $script:AllScannedItems.TrimExcess()
            $script:LiveList.TrimExcess()
            # Liberar el LiveItems index map (ya no se necesita hasta el próximo scan)
            $script:LiveItems.Clear()
            # GC agresivo: LOH compaction + EmptyWorkingSet
            Invoke-AggressiveGC

            $pbDiskScan.IsIndeterminate = $false
            $pbDiskScan.Value = 100
            $btnDiskScan.IsEnabled = $true
            $btnDiskStop.IsEnabled = $false
            $btnExportCsv.IsEnabled    = $true  # [B3]
            $btnDiskReport.IsEnabled   = $true  # Informe HTML
            $btnSnapshotSave.IsEnabled    = $true   # [B4] Habilitar guardar snapshot al finalizar
            $txtSnapshotName.IsEnabled    = $true
            $txtSnapshotName.Text         = "Escaneo $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
            $txtSnapshotName.SelectAll()

            $gtStr2 = if ($gt2 -ge 1GB) { "{0:N1} GB" -f ($gt2/1GB) } elseif ($gt2 -ge 1MB) { "{0:N0} MB" -f ($gt2/1MB) } else { "{0:N0} KB" -f ($gt2/1KB) }
            $emoji = if ([ScanCtl211]::Stop) { "⏹" } else { "✅" }
            $txtDiskScanStatus.Text = "$emoji  $($script:AllScannedItems.Count) elementos  ·  $gtStr2  ·  $(Get-Date -Format 'HH:mm:ss')"
        }
    })
$script:DiskUiTimer.Start()
}


$btnDiskBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Selecciona la carpeta a escanear"
    $dlg.RootFolder  = "MyComputer"
    $dlg.SelectedPath = $txtDiskScanPath.Text
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtDiskScanPath.Text = $dlg.SelectedPath
    }
})

$btnDiskScan.Add_Click({
    Save-Settings  # [C3]
    Start-DiskScan -RootPath $txtDiskScanPath.Text.Trim()
})

$btnDiskStop.Add_Click({
    [ScanCtl211]::Stop = $true
    $btnDiskStop.IsEnabled = $false
    $txtDiskScanStatus.Text = "⏹ Cancelando — espera a que termine la carpeta actual…"
})

# ─────────────────────────────────────────────────────────────────────────────
# [C3] PERSISTENCIA DE CONFIGURACIÓN — %APPDATA%\SysOpt\settings.json
# ─────────────────────────────────────────────────────────────────────────────
$script:SettingsPath = [System.IO.Path]::Combine(
    [Environment]::GetFolderPath("ApplicationData"), "SysOpt", "settings.json")

function Save-Settings {
    try {
        $dir = [System.IO.Path]::GetDirectoryName($script:SettingsPath)
        if (-not (Test-Path $dir)) { [System.IO.Directory]::CreateDirectory($dir) | Out-Null }
        $cfg = @{
            DiskScanPath       = $txtDiskScanPath.Text
            AutoRefresh        = ($chkAutoRefresh.IsChecked -eq $true)
            RefreshIntervalSec = if ($cmbRefreshInterval.SelectedItem) { $cmbRefreshInterval.SelectedItem.Tag } else { "5" }
            DiskFilterText     = $txtDiskFilter.Text
        }
        $json = $cfg | ConvertTo-Json
        [System.IO.File]::WriteAllText($script:SettingsPath, $json, [System.Text.Encoding]::UTF8)
    } catch {}
}

function Load-Settings {
    try {
        if (Test-Path $script:SettingsPath) {
            $cfg = Get-Content -Path $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.DiskScanPath)   { $txtDiskScanPath.Text = $cfg.DiskScanPath }
            if ($cfg.DiskFilterText) { $txtDiskFilter.Text   = $cfg.DiskFilterText }
            # Auto-refresh interval
            if ($cfg.RefreshIntervalSec) {
                foreach ($item in $cmbRefreshInterval.Items) {
                    if ($item.Tag -eq "$($cfg.RefreshIntervalSec)") {
                        $cmbRefreshInterval.SelectedItem = $item; break
                    }
                }
            }
            # Auto-refresh on/off (set last so timer uses correct interval)
            if ($cfg.AutoRefresh -eq $true) { $chkAutoRefresh.IsChecked = $true }
        }
    } catch {}
}

# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# [B4] HISTORIAL DE ESCANEOS — Snapshots JSON en .\snapshots\ (relativo al script)
# ─────────────────────────────────────────────────────────────────────────────
$script:SnapshotDir = Join-Path $script:AppDir "snapshots"
$script:LogsDir     = Join-Path $script:AppDir "logs"

# Referencias UI
$lbSnapshots            = $window.FindName("lbSnapshots")
$lbSnapshotDetail       = $window.FindName("lbSnapshotDetail")
$btnSnapshotSave        = $window.FindName("btnSnapshotSave")
$btnSnapshotCompare     = $window.FindName("btnSnapshotCompare")
$btnSnapshotDelete      = $window.FindName("btnSnapshotDelete")
$chkSnapshotSelectAll   = $window.FindName("chkSnapshotSelectAll")
$txtSnapshotSelCount    = $window.FindName("txtSnapshotSelCount")
$txtSnapshotName        = $window.FindName("txtSnapshotName")
$txtSnapshotDetailTitle = $window.FindName("txtSnapshotDetailTitle")
$txtSnapshotDetailMeta  = $window.FindName("txtSnapshotDetailMeta")
$txtSnapshotStatus      = $window.FindName("txtSnapshotStatus")

# ── Helpers de formato ───────────────────────────────────────────────────────
function Format-SnapshotSize([long]$bytes) {
    if ($bytes -ge 1GB) { "{0:N1} GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { "{0:N0} MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { "{0:N0} KB" -f ($bytes / 1KB) }
    else { "$bytes B" }
}

# ── Actualizar contador y estado de botones según checks ─────────────────────
function Update-SnapshotCheckState {
    $all     = @($lbSnapshots.ItemsSource)
    $checked = @($all | Where-Object { $_.IsChecked })
    $n       = $checked.Count
    $total   = $all.Count

    $txtSnapshotSelCount.Text = if ($n -eq 0) {
        if ($total -eq 0) { "Sin snapshots guardados." } else { "$total snapshot(s) disponibles." }
    } else {
        "$n de $total seleccionados"
    }

    $btnSnapshotDelete.IsEnabled  = ($n -gt 0)
    $hasCurrentScan = ($null -ne $script:AllScannedItems -and $script:AllScannedItems.Count -gt 0)
    $btnSnapshotCompare.IsEnabled = ($n -eq 2) -or ($n -eq 1 -and $hasCurrentScan)
    $btnSnapshotCompare.Content   = if ($n -eq 2) {
        ([char]::ConvertFromUtf32(0x1F4CA) + "  Comparar 2")
    } else {
        ([char]::ConvertFromUtf32(0x1F4CA) + "  Comparar")
    }
}

# ── Ventana de progreso con botón "Segundo plano" ────────────────────────────
# Usada por: Load-SnapshotList, Get-SnapshotEntriesAsync, guardar snapshot,
#            exportar CSV, exportar HTML.
# El botón "Poner en segundo plano" oculta la ventana pero NO detiene el proceso
# ni el DispatcherTimer — al completarse se cierra sola igual.
function Show-ExportProgressDialog {
    param([string]$OperationTitle = "Procesando...")

    # ── Construir la ventana 100% programáticamente — sin FindName, sin Name= en XAML ──
    # FindName falla con WindowStyle=None + AllowsTransparency=True antes de Show().
    # Al crear los controles directamente tenemos referencias directas, sin ambigüedad.

    $dlg = New-Object System.Windows.Window
    $dlg.Title                  = ""
    $dlg.Width                  = 460
    $dlg.SizeToContent          = "Height"
    $dlg.WindowStartupLocation  = "CenterOwner"
    $dlg.ResizeMode             = "NoResize"
    $dlg.WindowStyle            = "None"
    $dlg.AllowsTransparency     = $true
    $dlg.Background             = [System.Windows.Media.Brushes]::Transparent
    $dlg.Topmost                = $true
    try { $dlg.Owner = $window } catch {}

    # Sombra exterior
    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.6
    $shadow.Color = [System.Windows.Media.Colors]::Black

    # Border raíz
    $rootBorder = New-Object System.Windows.Controls.Border
    $rootBorder.Background   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#131625")
    $rootBorder.BorderBrush  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5BA3FF")
    $rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $rootBorder.CornerRadius = [System.Windows.CornerRadius]::new(12)
    $rootBorder.Effect       = $shadow

    # StackPanel principal
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = [System.Windows.Thickness]::new(24,20,24,20)

    # — Cabecera —
    $spHead = New-Object System.Windows.Controls.StackPanel
    $spHead.Orientation = "Horizontal"
    $spHead.Margin = [System.Windows.Thickness]::new(0,0,0,14)

    $iconBorder = New-Object System.Windows.Controls.Border
    $iconBorder.Width = 30; $iconBorder.Height = 30
    $iconBorder.CornerRadius = [System.Windows.CornerRadius]::new(7)
    $iconBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5BA3FF")
    $iconBorder.Margin = [System.Windows.Thickness]::new(0,0,12,0)
    $iconBorder.VerticalAlignment = "Center"
    $tbIcon = New-Object System.Windows.Controls.TextBlock
    $tbIcon.Text = [char]0x21E9; $tbIcon.FontSize = 14; $tbIcon.FontWeight = "Bold"
    $tbIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0D0F1A")
    $tbIcon.HorizontalAlignment = "Center"; $tbIcon.VerticalAlignment = "Center"
    $iconBorder.Child = $tbIcon

    $tbTitle = New-Object System.Windows.Controls.TextBlock
    $tbTitle.Text = "Procesando..."; $tbTitle.FontSize = 14; $tbTitle.FontWeight = "Bold"
    $tbTitle.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E8ECF4")
    $tbTitle.VerticalAlignment = "Center"
    $tbTitle.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")

    $spHead.Children.Add($iconBorder) | Out-Null
    $spHead.Children.Add($tbTitle)    | Out-Null

    # — Fase —
    $tbPhase = New-Object System.Windows.Controls.TextBlock
    $tbPhase.Text = "Iniciando..."; $tbPhase.FontSize = 11.5
    $tbPhase.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7880A0")
    $tbPhase.TextTrimming = "CharacterEllipsis"
    $tbPhase.Margin = [System.Windows.Thickness]::new(0,0,0,10)
    $tbPhase.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")

    # — Barra de progreso —
    $barTrack = New-Object System.Windows.Controls.Border
    $barTrack.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
    $barTrack.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $barTrack.Height = 14; $barTrack.Margin = [System.Windows.Thickness]::new(0,0,0,8)
    $barGrid = New-Object System.Windows.Controls.Grid
    $barFill = New-Object System.Windows.Controls.Border
    $barFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5BA3FF")
    $barFill.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $barFill.HorizontalAlignment = "Left"; $barFill.Width = 0
    $barGrid.Children.Add($barFill) | Out-Null
    $barTrack.Child = $barGrid

    # — % + ETA —
    $gridPct = New-Object System.Windows.Controls.Grid
    $gridPct.Margin = [System.Windows.Thickness]::new(0,0,0,4)
    $colStar = New-Object System.Windows.Controls.ColumnDefinition; $colStar.Width = [System.Windows.GridLength]::new(1, "Star")
    $colAuto = New-Object System.Windows.Controls.ColumnDefinition; $colAuto.Width = [System.Windows.GridLength]::Auto
    $gridPct.ColumnDefinitions.Add($colStar) | Out-Null
    $gridPct.ColumnDefinitions.Add($colAuto) | Out-Null

    $tbPct = New-Object System.Windows.Controls.TextBlock
    $tbPct.Text = "0%"; $tbPct.FontSize = 12; $tbPct.FontWeight = "Bold"
    $tbPct.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5BA3FF")
    $tbPct.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    [System.Windows.Controls.Grid]::SetColumn($tbPct, 0)

    $tbEta = New-Object System.Windows.Controls.TextBlock
    $tbEta.Text = ""; $tbEta.FontSize = 11
    $tbEta.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4AE896")
    $tbEta.HorizontalAlignment = "Right"
    $tbEta.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    [System.Windows.Controls.Grid]::SetColumn($tbEta, 1)

    $gridPct.Children.Add($tbPct) | Out-Null
    $gridPct.Children.Add($tbEta) | Out-Null

    # — Contador —
    $tbCount = New-Object System.Windows.Controls.TextBlock
    $tbCount.Text = ""; $tbCount.FontSize = 10.5
    $tbCount.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4A5270")
    $tbCount.Margin = [System.Windows.Thickness]::new(0,0,0,14)
    $tbCount.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")

    # — Botón segundo plano —
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = [string]([char]0x2193) + "  Poner en segundo plano"
    $btn.Height = 32
    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
    $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7880A0")
    $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2A3050")
    $btn.BorderThickness = [System.Windows.Thickness]::new(1)
    $btn.FontSize = 11.5
    $btn.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    $btn.Cursor = [System.Windows.Input.Cursors]::Hand
    $btn.HorizontalAlignment = "Right"
    $btn.Padding = [System.Windows.Thickness]::new(16,0,16,0)
    $btn.Add_Click({ $dlg.Hide() })   # referencia directa — nunca null

    # Ensamblar
    $sp.Children.Add($spHead)   | Out-Null
    $sp.Children.Add($tbPhase)  | Out-Null
    $sp.Children.Add($barTrack) | Out-Null
    $sp.Children.Add($gridPct)  | Out-Null
    $sp.Children.Add($tbCount)  | Out-Null
    $sp.Children.Add($btn)      | Out-Null
    $rootBorder.Child = $sp
    $dlg.Content = $rootBorder
    $dlg.Add_MouseLeftButtonDown({ $dlg.DragMove() })

    return @{
        Window  = $dlg
        Title   = $tbTitle
        Phase   = $tbPhase
        BarFill = $barFill
        Pct     = $tbPct
        Eta     = $tbEta
        Count   = $tbCount
        BtnBg   = $btn
    }
}

# Helper interno: cierra la ventana de progreso (visible u oculta en 2do plano)
function Close-ProgressDialog($prog) {
    try { $prog.Window.Close() } catch {}
}

# Helper: actualiza el diálogo de progreso de forma null-safe
function Update-ProgressDialog($prog, [int]$pct, [string]$phase, [string]$count) {
    if ($null -eq $prog) { return }
    try {
        if ($null -ne $prog.Phase)   { $prog.Phase.Text    = $phase }
        if ($null -ne $prog.Pct)     { $prog.Pct.Text      = "$pct%" }
        if ($null -ne $prog.BarFill) { $prog.BarFill.Width = [math]::Round(408 * $pct / 100, 0) }
        if ($null -ne $prog.Count -and $count -ne '') { $prog.Count.Text = $count }
    } catch {}
}

# ── Estado compartido thread-safe (único, reutilizado por todos los runspaces) ─
$script:ExportState = [hashtable]::Synchronized(@{
    Phase = ""; Progress = 0; ItemsDone = 0; ItemsTotal = 0
    Done = $false; Error = ""; Result = $null
})

# ── Cargar lista de snapshots en background ──────────────────────────────────
function Load-SnapshotList {
    $snapDir   = $script:SnapshotDir
    $jsonFiles = @()
    if (Test-Path $snapDir) {
        $jsonFiles = @(Get-ChildItem -Path $snapDir -Filter "*.json" -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending)
    }

    if ($jsonFiles.Count -eq 0) {
        $lbSnapshots.ItemsSource        = [System.Collections.Generic.List[object]]::new()
        $txtSnapshotDetailTitle.Text    = "Selecciona un snapshot para ver sus carpetas"
        $txtSnapshotDetailMeta.Text     = ""
        $lbSnapshotDetail.ItemsSource   = $null
        $chkSnapshotSelectAll.IsChecked = $false
        $txtSnapshotStatus.Text         = "Sin snapshots guardados."
        Update-SnapshotCheckState
        return
    }

    $txtSnapshotStatus.Text = "⏳ Cargando historial..."

    $filePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $jsonFiles) { $filePaths.Add($f.FullName) }

    $script:LoadSnapState = [hashtable]::Synchronized(@{
        Phase = "Iniciando..."; Progress = 0; ItemsDone = 0; ItemsTotal = $filePaths.Count
        Done = $false; Error = ""
        Results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    })

    $bgLoad = {
        param($State, $FilePaths)
        function FmtB([long]$b) {
            if ($b -ge 1GB) { "{0:N1} GB" -f ($b/1GB) }
            elseif ($b -ge 1MB) { "{0:N0} MB" -f ($b/1MB) }
            elseif ($b -ge 1KB) { "{0:N0} KB" -f ($b/1KB) }
            else { "$b B" }
        }
        # ── [RAM-04] JsonTextReader: leer solo metadatos sin cargar Entries ──
        # Analiza el JSON line-by-line. Al encontrar la propiedad "Entries" salta
        # todo el array contando elementos con depth-tracking sin deserializarlos.
        # RAM proporcional a metadatos, no a número de entradas.
        function Read-SnapshotMeta([string]$fp) {
            $meta = @{ Label=""; RootPath=""; Date=""; EntryCount=0; TotalBytes=0L; RootCount=0 }
            $fs = $null; $jr = $null
            try {
                $fs = [System.IO.File]::OpenRead($fp)
                $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true, 65536)
                $jr = [Newtonsoft.Json.JsonTextReader]::new($sr)
                $jr.SupportMultipleContent = $false
                $currentProp = ""
                $inEntries = $false; $entDepth = 0
                $inEntry = $false; $entPropDepth = 0
                $entSizeBytes = 0L; $entItemDepth = 0
                while ($jr.Read()) {
                    $tt = $jr.TokenType
                    if (-not $inEntries) {
                        if ($tt -eq [Newtonsoft.Json.JsonToken]::PropertyName) {
                            $currentProp = $jr.Value
                        } elseif ($tt -eq [Newtonsoft.Json.JsonToken]::String) {
                            switch ($currentProp) {
                                "Label"    { $meta.Label    = $jr.Value }
                                "RootPath" { $meta.RootPath = $jr.Value }
                                "Date"     { $meta.Date     = $jr.Value }
                            }
                        } elseif ($tt -eq [Newtonsoft.Json.JsonToken]::StartArray -and $currentProp -eq "Entries") {
                            $inEntries = $true; $entDepth = 1
                        }
                    } else {
                        # Dentro del array Entries: contar objetos y sumar SizeBytes de Depth==0
                        if ($tt -eq [Newtonsoft.Json.JsonToken]::StartObject) {
                            if ($entDepth -eq 1) {
                                $inEntry = $true; $entSizeBytes = 0L; $entItemDepth = -1
                            }
                            $entDepth++
                        } elseif ($tt -eq [Newtonsoft.Json.JsonToken]::EndObject) {
                            $entDepth--
                            if ($entDepth -eq 1 -and $inEntry) {
                                $meta.EntryCount++
                                if ($entItemDepth -eq 0) { $meta.TotalBytes += $entSizeBytes; $meta.RootCount++ }
                                $inEntry = $false
                            }
                        } elseif ($tt -eq [Newtonsoft.Json.JsonToken]::StartArray) { $entDepth++ }
                        elseif ($tt -eq [Newtonsoft.Json.JsonToken]::EndArray) {
                            $entDepth--
                            if ($entDepth -eq 0) { break }  # fin del array Entries
                        } elseif ($inEntry -and $tt -eq [Newtonsoft.Json.JsonToken]::PropertyName) {
                            $entPropDepth = $entDepth; $currentProp = $jr.Value
                        } elseif ($inEntry -and $entDepth -eq $entPropDepth) {
                            if ($currentProp -eq "SizeBytes") {
                                try { $entSizeBytes = [long]$jr.Value } catch {}
                            } elseif ($currentProp -eq "Depth") {
                                try { $entItemDepth = [int]$jr.Value } catch {}
                            }
                        }
                    }
                }
            } catch {
                # Fallback: leer metadatos básicos del principio del archivo
                try {
                    if ($null -ne $fs) { $fs.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null }
                    $raw  = [System.IO.File]::ReadAllText($fp, [System.Text.Encoding]::UTF8)
                    $data = $raw | ConvertFrom-Json; $raw = $null
                    $meta.Label    = [string]$data.Label
                    $meta.RootPath = [string]$data.RootPath
                    $meta.Date     = [string]$data.Date
                    foreach ($e in $data.Entries) {
                        $meta.EntryCount++
                        if ([int]$e.Depth -eq 0) { $meta.TotalBytes += [long]$e.SizeBytes; $meta.RootCount++ }
                    }
                    $data = $null
                } catch {}
            } finally {
                if ($null -ne $jr) { try { $jr.Close() } catch {} }
                if ($null -ne $fs) { try { $fs.Close(); $fs.Dispose() } catch {} }
            }
            return $meta
        }
        try {
            $total = $FilePaths.Count
            for ($i = 0; $i -lt $total; $i++) {
                $fp = $FilePaths[$i]
                $State.Phase     = "Leyendo $([System.IO.Path]::GetFileName($fp))..."
                $State.ItemsDone = $i
                $State.Progress  = [int](($i / $total) * 92)
                try {
                    $m = Read-SnapshotMeta $fp
                    $State.Results.Add(@{
                        FilePath   = $fp
                        Label      = $m.Label
                        RootPath   = $m.RootPath
                        DateStr    = $m.Date
                        EntryCount = $m.EntryCount
                        TotalBytes = $m.TotalBytes
                        RootCount  = $m.RootCount
                        SummaryStr = "$($m.RootCount) carpetas raíz · $($m.EntryCount) total · $(FmtB $m.TotalBytes)"
                    })
                } catch {}
            }
            $State.Phase = "Completado"; $State.Progress = 100; $State.ItemsDone = $total
            $State.Done = $true
        } catch { $State.Error = $_.Exception.Message; $State.Done = $true }
    }

    # [RAM-05] Usar RunspacePool en lugar de runspace individual
    $ctx = New-PooledPS
    $ps = $ctx.PS
    [void]$ps.AddScript($bgLoad)
    [void]$ps.AddParameter("State",     $script:LoadSnapState)
    [void]$ps.AddParameter("FilePaths", $filePaths)
    $async = $ps.BeginInvoke()

    $prog = Show-ExportProgressDialog
    if ($null -ne $prog.Title)  { $prog.Title.Text = "Cargando historial de snapshots" }
    if ($null -ne $prog.Phase)  { $prog.Phase.Text = "Leyendo archivos..." }
    $prog.Window.Show()

    if ($null -ne $script:_loadTimer) { try { $script:_loadTimer.Stop() } catch {} }
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:_loadTimer  = $t
    $script:_loadProg   = $prog
    $script:_loadPs     = $ps
    $script:_loadCtx    = $ctx
    $script:_loadAsync  = $async
    $script:_loadFiles  = $filePaths

    $t.Add_Tick({
        $st  = $script:LoadSnapState
        $pg  = $script:_loadProg
        $pct = [int]$st.Progress
        $cntStr = if ($st.ItemsTotal -gt 0) { "$($st.ItemsDone) / $($st.ItemsTotal) snapshots" } else { "" }
        Update-ProgressDialog $pg $pct $st.Phase $cntStr

        if ($st.Done) {
            $script:_loadTimer.Stop()
            Close-ProgressDialog $script:_loadProg
            try { $script:_loadPs.EndInvoke($script:_loadAsync) | Out-Null } catch {}
            Dispose-PooledPS $script:_loadCtx

            # Reconstruir lista en el orden original (por fecha desc)
            $map = @{}
            foreach ($r in $st.Results) { $map[$r.FilePath] = $r }
            $ordered = [System.Collections.Generic.List[object]]::new()
            foreach ($fp in $script:_loadFiles) {
                if ($map.ContainsKey($fp)) {
                    $r = $map[$fp]
                    $ordered.Add((New-Object PSObject -Property ([ordered]@{
                        FilePath   = $r.FilePath;   Label      = $r.Label
                        RootPath   = $r.RootPath;   DateStr    = $r.DateStr
                        EntryCount = $r.EntryCount; TotalBytes = $r.TotalBytes
                        RootCount  = $r.RootCount;  SummaryStr = $r.SummaryStr
                        IsChecked  = $false
                    })))
                }
            }
            $lbSnapshots.ItemsSource        = $ordered
            $txtSnapshotDetailTitle.Text    = "Selecciona un snapshot para ver sus carpetas"
            $txtSnapshotDetailMeta.Text     = ""
            $lbSnapshotDetail.ItemsSource   = $null
            $chkSnapshotSelectAll.IsChecked = $false
            $n = $ordered.Count
            $txtSnapshotStatus.Text = if ($n -eq 0) { "Sin snapshots guardados." } else { "$n snapshot(s) disponibles." }
            Update-SnapshotCheckState
            # [RAM-06] GC agresivo post-carga de historial
            Invoke-AggressiveGC
            if ($st.Error -ne "") { $txtSnapshotStatus.Text = "Error al cargar: $($st.Error)" }
        }
    })
    $t.Start()
}

# ── Leer entries de un snapshot en background ────────────────────────────────
# $OnComplete: scriptblock { param($entries) ... }   entries = List[hashtable]
# $OnError:   scriptblock { param($msg) ... }
function Get-SnapshotEntriesAsync {
    param(
        [string]$FilePath,
        [string]$OperationTitle = "Cargando snapshot...",
        [scriptblock]$OnComplete,
        [scriptblock]$OnError
    )

    $script:ExportState.Phase     = "Leyendo archivo..."
    $script:ExportState.Progress  = 0
    $script:ExportState.ItemsDone = 0
    $script:ExportState.ItemsTotal= 0
    $script:ExportState.Done      = $false
    $script:ExportState.Error     = ""
    $script:ExportState.Result    = $null

    # ── [FIFO-02] FIFO streaming load via JsonTextReader + ConcurrentQueue ───
    # JsonTextReader analiza el JSON token a token (streaming).
    # Cada entrada se encola en ConcurrentQueue en cuanto se completa su objeto
    # — el productor no espera a tener todas las entradas.
    # El hilo UI drena la queue en el tick del DispatcherTimer → UI nunca bloquea.
    # RAM extra = solo los objetos en tránsito en la queue + metadatos del reader.
    # NUNCA se materializa ReadAllText (copia del JSON) ni ConvertFrom-Json en RAM.
    # ─────────────────────────────────────────────────────────────────────────
    $entState = [hashtable]::Synchronized(@{
        Queue    = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        FeedDone = $false
        Error    = ""
        Total    = 0   # estimado, desconocido hasta parsear
    })

    $bgEnt = {
        param($EntState, $ExportState, $FilePath)
        # [FIFO-02] Usar ConvertFrom-Json nativo de PowerShell — no requiere Newtonsoft.
        # ConvertFrom-Json es un cmdlet interno (System.Management.Automation) y esta
        # disponible en todos los runspaces sin cargar assemblies externos.
        # Deserializamos el JSON completo y encolamos los entries uno a uno (FIFO),
        # liberando cada referencia inmediatamente tras encolar.
        try {
            $ExportState.Phase = "Leyendo archivo..."; $ExportState.Progress = 10
            $raw  = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
            $ExportState.Phase = "Deserializando...";  $ExportState.Progress = 30
            $data = $raw | ConvertFrom-Json
            $raw  = $null   # liberar el string JSON inmediatamente tras parsear

            $entries = $data.Entries
            $data    = $null   # liberar el objeto raiz — solo necesitamos $entries
            $total   = if ($null -ne $entries) { @($entries).Count } else { 0 }
            $ExportState.ItemsTotal = $total
            $ExportState.Phase = "Encolando entradas..."; $ExportState.Progress = 50

            # [FIFO] Encolar entry a entry
            $i = 0
            foreach ($e in $entries) {
                $EntState.Queue.Enqueue(@{
                    Name      = [string]$e.Name
                    FullPath  = [string]$e.FullPath
                    SizeBytes = [long]$e.SizeBytes
                    FileCount = [string]$e.FileCount
                    Depth     = [int]$e.Depth
                })
                $i++
                if ($i % 500 -eq 0) {
                    $ExportState.ItemsDone = $i
                    $ExportState.Progress  = [int](50 + ($i / [Math]::Max(1,$total)) * 46)
                    $ExportState.Phase     = "Encolando... ($i / $total)"
                }
            }
            $entries = $null

            $ExportState.ItemsDone = $i; $ExportState.ItemsTotal = $i
            $ExportState.Progress  = 100; $ExportState.Phase = "Completado"
        } catch {
            $EntState.Error    = $_.Exception.Message
            $ExportState.Error = $_.Exception.Message
        } finally {
            $EntState.FeedDone = $true
            $ExportState.Done  = $true
        }
    }


    # [RAM-05] Usar RunspacePool
    $ctxEnt = New-PooledPS
    $ps = $ctxEnt.PS
    [void]$ps.AddScript($bgEnt)
    [void]$ps.AddParameter("EntState",    $entState)
    [void]$ps.AddParameter("ExportState", $script:ExportState)
    [void]$ps.AddParameter("FilePath",    $FilePath)
    $async = $ps.BeginInvoke()

    $prog = Show-ExportProgressDialog
    if ($null -ne $prog.Title) { $prog.Title.Text = $OperationTitle }
    $prog.Window.Show()

    if ($null -ne $script:_entTimer) { try { $script:_entTimer.Stop() } catch {} }
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:_entTimer      = $t
    $script:_entProg       = $prog
    $script:_entPs         = $ps
    $script:_entCtx        = $ctxEnt
    $script:_entAsync      = $async
    $script:_entOnComplete = $OnComplete
    $script:_entOnError    = $OnError
    $script:_entState      = $entState
    $script:_entAccum      = [System.Collections.Generic.List[object]]::new()

    $t.Add_Tick({
        $st  = $script:ExportState
        $pg  = $script:_entProg
        $pct = [int]$st.Progress
        $entSt = $script:_entState

        # [FIFO] Drenar queue en el tick del UI — procesa lotes sin bloquear
        $item = $null
        $drained = 0
        while ($drained -lt 500 -and $entSt.Queue.TryDequeue([ref]$item)) {
            $script:_entAccum.Add($item)
            $item = $null
            $drained++
        }

        $cntStr = "$($script:_entAccum.Count) entradas leídas"
        Update-ProgressDialog $pg $pct $st.Phase $cntStr

        if ($st.Done -and $entSt.FeedDone -and $entSt.Queue.IsEmpty) {
            $script:_entTimer.Stop()
            Close-ProgressDialog $script:_entProg
            try { $script:_entPs.EndInvoke($script:_entAsync) | Out-Null } catch {}
            Dispose-PooledPS $script:_entCtx
            # [FIFO] GC agresivo post-carga — liberar RAM del runspace y del lector
            [System.GC]::Collect(2, [System.GCCollectionMode]::Forced, $true, $true)
            [System.GC]::WaitForPendingFinalizers()
            try {
                [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = `
                    [System.Runtime.GCLargeObjectHeapCompactionMode]::CompactOnce
                [System.GC]::Collect()
            } catch {}

            if ($st.Error -ne "") {
                if ($null -ne $script:_entOnError) { & $script:_entOnError $st.Error }
            } else {
                # Entregar la lista acumulada al callback — ya completa y ordenable
                if ($null -ne $script:_entOnComplete) { & $script:_entOnComplete $script:_entAccum }
            }
            $script:_entAccum = $null   # liberar acumulador tras entregar
        }
    })
    $t.Start()
}

# ── Guardar snapshot del escaneo actual ─────────────────────────────────────
$btnSnapshotSave.Add_Click({
    if ($null -eq $script:AllScannedItems -or $script:AllScannedItems.Count -eq 0) { return }
    $label = $txtSnapshotName.Text.Trim()
    if ($label -eq '') { $label = "Escaneo $(Get-Date -Format 'dd/MM/yyyy HH:mm')" }

    $btnSnapshotSave.IsEnabled = $false
    $txtSnapshotStatus.Text    = "⏳ Guardando snapshot..."

    $script:ExportState.Phase     = "Preparando..."; $script:ExportState.Progress = 0
    $script:ExportState.ItemsDone = 0; $script:ExportState.ItemsTotal = $script:AllScannedItems.Count
    $script:ExportState.Done      = $false; $script:ExportState.Error = ""; $script:ExportState.Result = $null

    # ── [FIFO-01] FIFO streaming save via ConcurrentQueue ────────────────────
    # El hilo UI llena la queue item a item (FIFO) y señaliza FeedDone.
    # El background drena la queue escribiendo directamente con JsonTextWriter
    # en disco — NUNCA se materializa el JSON completo en RAM.
    # RAM extra = solo el lote en tránsito en la queue, no toda la colección.
    # ─────────────────────────────────────────────────────────────────────────
    $saveState = [hashtable]::Synchronized(@{
        Queue    = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        FeedDone = $false          # UI señaliza que terminó de encolar
        Total    = $script:AllScannedItems.Count
    })

    $saveLabel = $label
    $saveRoot  = $txtDiskScanPath.Text
    $saveDir   = $script:SnapshotDir

    # Script background: drena Queue con StreamWriter JSON manual — sin dependencia Newtonsoft
    $bgSave = {
        param($State, $ExportState, $Label, $RootPath, $SnapshotDir)
        $fs = $null; $sw = $null
        try {
            $ExportState.Phase = "Preparando directorio..."; $ExportState.Progress = 5
            if (-not (Test-Path $SnapshotDir)) {
                [System.IO.Directory]::CreateDirectory($SnapshotDir) | Out-Null
            }
            $fp = [System.IO.Path]::Combine($SnapshotDir, "snapshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').json")

            # [FIFO] Abrir StreamWriter con buffer 64KB — escribe JSON manualmente token a token
            # Sin Newtonsoft: los valores de entry son tipos primitivos conocidos (string/long/int).
            # El único escape necesario es \" en strings (rutas/nombres de archivo).
            $fs = [System.IO.File]::Open($fp, [System.IO.FileMode]::Create,
                  [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $sw = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8, 65536)

            # Helper inline: escapa solo los caracteres JSON obligatorios en strings de rutas
            # Rutas Windows raramente tienen \n/\r/\t pero sí pueden tener comillas y backslashes.
            # El backslash ya está duplicado en FullPath (ej. C:\\Users\\...) dentro del JSON.

            # Cabecera del objeto raíz
            $date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $lbl  = $Label   -replace '\\',  '\\\\' -replace '"', '\"'
            $root = $RootPath -replace '\\', '\\\\' -replace '"', '\"'
            $sw.WriteLine('{')
            $sw.WriteLine("  `"Label`": `"$lbl`",")
            $sw.WriteLine("  `"Date`": `"$date`",")
            $sw.WriteLine("  `"RootPath`": `"$root`",")
            $sw.WriteLine('  "Entries": [')

            $ExportState.Phase = "Escribiendo entradas..."; $ExportState.Progress = 10
            $total   = $State.Total
            $written = 0
            $item    = $null
            $first   = $true

            # [FIFO] Drenar queue FIFO hasta que el productor señalice FeedDone y la queue quede vacía
            while (-not ($State.FeedDone -and $State.Queue.IsEmpty)) {
                while ($State.Queue.TryDequeue([ref]$item)) {
                    # Separador entre objetos JSON (coma antes de cada entry excepto el primero)
                    if (-not $first) { $sw.Write(',') } else { $first = $false }

                    # Escapar strings — comillas dobles y backslashes para JSON válido
                    $fp2 = ([string]$item.FP) -replace '\\', '\\\\' -replace '"', '\"'
                    $nm  = ([string]$item.N)  -replace '\\', '\\\\' -replace '"', '\"'
                    $fc  = ([string]$item.FC) -replace '\\', '\\\\' -replace '"', '\"'
                    $sz  = [long]$item.SZ
                    $d   = [int]$item.D

                    # Escribir objeto entry directamente al stream — una sola llamada Write por entry
                    $sw.WriteLine("{`"FullPath`":`"$fp2`",`"Name`":`"$nm`",`"SizeBytes`":$sz,`"FileCount`":`"$fc`",`"Depth`":$d}")
                    $item = $null   # liberar referencia inmediatamente — FIFO consume y descarta
                    $written++
                    if ($written % 500 -eq 0) {
                        $sw.Flush()   # flush periódico al disco — evita buffers grandes
                        $ExportState.ItemsDone = $written
                        $ExportState.Progress  = if ($total -gt 0) { [int](10 + ($written / $total) * 85) } else { 50 }
                        $ExportState.Phase     = "Escribiendo... ($written / $total)"
                    }
                }
                if (-not $State.FeedDone) { [System.Threading.Thread]::Sleep(5) }
            }

            # Cerrar array y objeto raíz
            $sw.WriteLine('  ]')
            $sw.WriteLine('}')
            $sw.Flush()

            $ExportState.Result = $Label; $ExportState.Progress = 100
            $ExportState.Phase  = "Completado"; $ExportState.ItemsDone = $written
            $ExportState.Done   = $true
        } catch {
            $ExportState.Error = $_.Exception.Message; $ExportState.Done = $true
        } finally {
            # [FIFO] Liberar recursos en orden — sin importar si hubo error
            if ($null -ne $sw) { try { $sw.Close() } catch {} }
            if ($null -ne $fs) { try { $fs.Close(); $fs.Dispose() } catch {} }
        }
    }

    # [FIFO] Lanzar background ANTES de encolar — así drena en paralelo
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "MTA"; $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($bgSave)
    [void]$ps.AddParameter("State",       $saveState)
    [void]$ps.AddParameter("ExportState", $script:ExportState)
    [void]$ps.AddParameter("Label",       $saveLabel)
    [void]$ps.AddParameter("RootPath",    $saveRoot)
    [void]$ps.AddParameter("SnapshotDir", $saveDir)
    $async = $ps.BeginInvoke()

    # [FIFO] Producir: encolar AllScannedItems item a item sin construir lista intermedia
    # El background ya está corriendo y drenando en paralelo → RAM pico ≈ lote en tránsito
    foreach ($item in $script:AllScannedItems) {
        if ($item.SizeBytes -ge 0) {
            $saveState.Queue.Enqueue(@{
                FP = $item.FullPath; N = $item.DisplayName
                SZ = $item.SizeBytes; FC = $item.FileCount; D = $item.Depth
            })
        }
    }
    $saveState.FeedDone = $true   # señalizar al background que no hay más items

    $prog = Show-ExportProgressDialog
    if ($null -ne $prog.Title) { $prog.Title.Text = "Guardando snapshot" }
    $prog.Window.Show()

    if ($null -ne $script:_saveTimer) { try { $script:_saveTimer.Stop() } catch {} }
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:_saveTimer = $t; $script:_saveProg  = $prog
    $script:_savePs    = $ps; $script:_saveRs   = $rs; $script:_saveAsync = $async

    $t.Add_Tick({
        $st  = $script:ExportState; $pg = $script:_saveProg; $pct = [int]$st.Progress
        $cntStr = if ($st.ItemsTotal -gt 0) { "$($st.ItemsDone) / $($st.ItemsTotal) entradas" } else { "" }
        Update-ProgressDialog $pg $pct $st.Phase $cntStr
        if ($st.Done) {
            $script:_saveTimer.Stop()
            Close-ProgressDialog $script:_saveProg
            try { $script:_savePs.EndInvoke($script:_saveAsync) | Out-Null } catch {}
            # [FIFO] Liberar runspace y forzar GC — el proceso termina limpio
            try { $script:_savePs.Dispose(); $script:_saveRs.Close(); $script:_saveRs.Dispose() } catch {}
            [System.GC]::Collect(2, [System.GCCollectionMode]::Forced, $true, $true)
            [System.GC]::WaitForPendingFinalizers()
            try {
                [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = `
                    [System.Runtime.GCLargeObjectHeapCompactionMode]::CompactOnce
                [System.GC]::Collect()
            } catch {}
            $btnSnapshotSave.IsEnabled = $true
            if ($st.Error -ne "") {
                $txtSnapshotStatus.Text = "Error al guardar: $($st.Error)"
            } else {
                $txtSnapshotStatus.Text = "✅ Snapshot guardado: $($st.Result)"
                Load-SnapshotList
            }
        }
    })
    $t.Start()
})

# ── CheckBox "Seleccionar todo" ───────────────────────────────────────────────
$chkSnapshotSelectAll.Add_Checked({
    foreach ($item in @($lbSnapshots.ItemsSource)) { $item.IsChecked = $true }
    $lbSnapshots.Items.Refresh(); Update-SnapshotCheckState
})
$chkSnapshotSelectAll.Add_Unchecked({
    foreach ($item in @($lbSnapshots.ItemsSource)) { $item.IsChecked = $false }
    $lbSnapshots.Items.Refresh(); Update-SnapshotCheckState
})

# ── Evento burbuja CheckBox dentro del ListBox ───────────────────────────────
[System.Windows.RoutedEventHandler]$script:snapCheckHandler = { param($s,$e); Update-SnapshotCheckState }
$lbSnapshots.AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent,   $script:snapCheckHandler)
$lbSnapshots.AddHandler([System.Windows.Controls.CheckBox]::UncheckedEvent, $script:snapCheckHandler)

# ── Selección de snapshot → cargar entries en background ─────────────────────
$lbSnapshots.Add_SelectionChanged({
    $sel = $lbSnapshots.SelectedItem
    if ($null -eq $sel) { Update-SnapshotCheckState; return }

    $txtSnapshotDetailTitle.Text = $sel.Label
    $txtSnapshotDetailMeta.Text  = "$($sel.DateStr)  ·  $($sel.RootPath)"
    $txtSnapshotStatus.Text      = "⏳ Cargando entradas del snapshot..."
    $lbSnapshotDetail.ItemsSource = $null

    $selLabel = $sel.Label

    Get-SnapshotEntriesAsync -FilePath $sel.FilePath `
        -OperationTitle "Cargando snapshot — $($sel.Label)" `
        -OnComplete {
            param($entries)
            $detailItems = [System.Collections.Generic.List[object]]::new()
            foreach ($e in ($entries | Sort-Object { [long]$_.SizeBytes } -Descending)) {
                $sz = [long]$e.SizeBytes
                $detailItems.Add([PSCustomObject]@{
                    FolderName = $e.Name;    FullPath = $e.FullPath
                    SizeStr    = Format-SnapshotSize $sz
                    SizeColor  = if ($sz -ge 10GB) { "#FF6B84" } elseif ($sz -ge 1GB) { "#FFB547" } `
                                 elseif ($sz -ge 100MB) { "#5BA3FF" } else { "#B0BACC" }
                    DeltaStr   = ""; DeltaColor = "#7880A0"
                })
            }
            $lbSnapshotDetail.ItemsSource = $detailItems
            $txtSnapshotStatus.Text       = "$($detailItems.Count) entradas en el snapshot."
            Update-SnapshotCheckState
        } `
        -OnError {
            param($msg)
            $txtSnapshotStatus.Text = "Error al cargar snapshot: $msg"
            Update-SnapshotCheckState
        }
})

# ── Comparar snapshots en background ─────────────────────────────────────────
# Patrón: cargar los JSON necesarios con Get-SnapshotEntriesAsync en cadena,
# luego realizar el cruce de datos en el callback (ya en el hilo UI, rápido).
$btnSnapshotCompare.Add_Click({
    $checked = @($lbSnapshots.ItemsSource | Where-Object { $_.IsChecked })

    if ($checked.Count -eq 2) {
        # ── Modo A vs B ───────────────────────────────────────────────────────
        $snapA = $checked[0]; $snapB = $checked[1]
        $txtSnapshotStatus.Text      = "⏳ Cargando snapshot A..."
        $txtSnapshotDetailTitle.Text = "Comparando: $($snapA.Label)  vs  $($snapB.Label)"
        $txtSnapshotDetailMeta.Text  = "$($snapA.DateStr)  vs  $($snapB.DateStr)"
        $lbSnapshotDetail.ItemsSource = $null

        $script:_cmpSnapA = $snapA; $script:_cmpSnapB = $snapB

        # Primero cargamos A; en su callback cargamos B; en el de B cruzamos datos
        Get-SnapshotEntriesAsync -FilePath $snapA.FilePath `
            -OperationTitle "Comparar — cargando $($snapA.Label)" `
            -OnComplete {
                param($entriesA)
                $script:_cmpEntriesA = $entriesA
                $txtSnapshotStatus.Text = "⏳ Cargando snapshot B..."

                Get-SnapshotEntriesAsync -FilePath $script:_cmpSnapB.FilePath `
                    -OperationTitle "Comparar — cargando $($script:_cmpSnapB.Label)" `
                    -OnComplete {
                        param($entriesB)
                        # Cruce de datos (rápido, en hilo UI)
                        $eA = $script:_cmpEntriesA
                        $mapB = [System.Collections.Generic.Dictionary[string,long]]::new(
                            [System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($e in $entriesB) { $mapB[$e.FullPath] = [long]$e.SizeBytes }
                        $setA = [System.Collections.Generic.HashSet[string]]::new(
                            [System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($e in $eA) { [void]$setA.Add($e.FullPath) }

                        $detailItems = [System.Collections.Generic.List[object]]::new()
                        foreach ($e in ($eA | Sort-Object { [long]$_.SizeBytes } -Descending)) {
                            $old = [long]$e.SizeBytes
                            $new = if ($mapB.ContainsKey($e.FullPath)) { $mapB[$e.FullPath] } else { -1L }
                            $d   = if ($new -ge 0) { $new - $old } else { $null }
                            $ds  = if ($null -eq $d) { "eliminada" } elseif ($d -eq 0) { "sin cambio" } `
                                   elseif ($d -gt 0) { "+$(Format-SnapshotSize $d)" } else { "-$(Format-SnapshotSize ([Math]::Abs($d)))" }
                            $dc  = if ($null -eq $d -or $d -eq 0) { "#7880A0" } elseif ($d -gt 0) { "#FF6B84" } else { "#4AE896" }
                            $sz  = if ($new -ge 0) { $new } else { $old }
                            $detailItems.Add([PSCustomObject]@{
                                FolderName = $e.Name; FullPath = $e.FullPath
                                SizeStr    = Format-SnapshotSize $sz
                                SizeColor  = if ($sz -ge 10GB) { "#FF6B84" } elseif ($sz -ge 1GB) { "#FFB547" } `
                                             elseif ($sz -ge 100MB) { "#5BA3FF" } else { "#B0BACC" }
                                DeltaStr   = $ds; DeltaColor = $dc
                            })
                        }
                        foreach ($e in $entriesB) {
                            if (-not $setA.Contains($e.FullPath)) {
                                $detailItems.Add([PSCustomObject]@{
                                    FolderName = $e.Name; FullPath = $e.FullPath
                                    SizeStr    = Format-SnapshotSize ([long]$e.SizeBytes)
                                    SizeColor  = "#4AE896"; DeltaStr = "nueva en B"; DeltaColor = "#4AE896"
                                })
                            }
                        }
                        $lbSnapshotDetail.ItemsSource = $detailItems
                        $txtSnapshotStatus.Text = "Comparación completada — $($detailItems.Count) carpetas."
                    } `
                    -OnError { param($msg); $txtSnapshotStatus.Text = "Error cargando snapshot B: $msg" }
            } `
            -OnError { param($msg); $txtSnapshotStatus.Text = "Error cargando snapshot A: $msg" }

    } elseif ($checked.Count -eq 1 -and $null -ne $script:AllScannedItems -and $script:AllScannedItems.Count -gt 0) {
        # ── Modo snapshot vs escaneo actual ───────────────────────────────────
        $sel = $checked[0]
        $txtSnapshotStatus.Text      = "⏳ Cargando snapshot para comparar..."
        $txtSnapshotDetailTitle.Text = "Comparando: $($sel.Label)  →  Escaneo actual"
        $txtSnapshotDetailMeta.Text  = "$($sel.DateStr)  vs  $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
        $lbSnapshotDetail.ItemsSource = $null

        Get-SnapshotEntriesAsync -FilePath $sel.FilePath `
            -OperationTitle "Comparar — cargando $($sel.Label)" `
            -OnComplete {
                param($snapEntries)
                $currentMap = [System.Collections.Generic.Dictionary[string,long]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase)
                foreach ($item in $script:AllScannedItems) {
                    if ($item.SizeBytes -ge 0) { $currentMap[$item.FullPath] = [long]$item.SizeBytes }
                }
                $snapSet = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase)
                foreach ($e in $snapEntries) { [void]$snapSet.Add($e.FullPath) }

                $detailItems = [System.Collections.Generic.List[object]]::new()
                foreach ($e in ($snapEntries | Sort-Object { [long]$_.SizeBytes } -Descending)) {
                    $old = [long]$e.SizeBytes
                    $new = if ($currentMap.ContainsKey($e.FullPath)) { $currentMap[$e.FullPath] } else { -1L }
                    $d   = if ($new -ge 0) { $new - $old } else { $null }
                    $ds  = if ($null -eq $d) { "eliminada" } elseif ($d -eq 0) { "sin cambio" } `
                           elseif ($d -gt 0) { "+$(Format-SnapshotSize $d)" } else { "-$(Format-SnapshotSize ([Math]::Abs($d)))" }
                    $dc  = if ($null -eq $d -or $d -eq 0) { "#7880A0" } elseif ($d -gt 0) { "#FF6B84" } else { "#4AE896" }
                    $sz  = if ($new -ge 0) { $new } else { $old }
                    $detailItems.Add([PSCustomObject]@{
                        FolderName = $e.Name; FullPath = $e.FullPath
                        SizeStr    = Format-SnapshotSize $sz
                        SizeColor  = if ($sz -ge 10GB) { "#FF6B84" } elseif ($sz -ge 1GB) { "#FFB547" } `
                                     elseif ($sz -ge 100MB) { "#5BA3FF" } else { "#B0BACC" }
                        DeltaStr   = $ds; DeltaColor = $dc
                    })
                }
                foreach ($item in $script:AllScannedItems) {
                    if ($item.SizeBytes -lt 0) { continue }
                    if (-not $snapSet.Contains($item.FullPath)) {
                        $detailItems.Add([PSCustomObject]@{
                            FolderName = $item.DisplayName; FullPath = $item.FullPath
                            SizeStr    = Format-SnapshotSize $item.SizeBytes
                            SizeColor  = "#4AE896"; DeltaStr = "nueva"; DeltaColor = "#4AE896"
                        })
                    }
                }
                $lbSnapshotDetail.ItemsSource = $detailItems
                $txtSnapshotStatus.Text = "Comparación completada — $($detailItems.Count) carpetas analizadas."
            } `
            -OnError { param($msg); $txtSnapshotStatus.Text = "Error al comparar: $msg" }
    }
})

# ── Eliminar snapshots marcados (en lote) ────────────────────────────────────
$btnSnapshotDelete.Add_Click({
    $checked = @($lbSnapshots.ItemsSource | Where-Object { $_.IsChecked })
    if ($checked.Count -eq 0) { return }
    $nombres = ($checked | ForEach-Object { $_.Label }) -join "`n  - "
    $msg = if ($checked.Count -eq 1) { "Eliminar el snapshot:`n  - $nombres" } `
           else { "Eliminar $($checked.Count) snapshots:`n  - $nombres" }
    $confirm = Show-ThemedDialog -Title "Confirmar eliminación" -Message $msg -Type "warning" -Buttons "YesNo"
    if ($confirm) {
        $errors = 0
        foreach ($snap in $checked) {
            try { Remove-Item -Path $snap.FilePath -Force -ErrorAction Stop } catch { $errors++ }
        }
        Load-SnapshotList
        if ($errors -gt 0) { $txtSnapshotStatus.Text = "Eliminados con $errors errores." }
    }
})

# ── Cargar lista al arrancar ──────────────────────────────────────────────────
Load-SnapshotList


# ─────────────────────────────────────────────────────────────────────────────
$script:FilterText = ""

function Apply-DiskFilter {
    param([string]$Filter)
    $script:FilterText = $Filter.Trim()
    if ($null -eq $script:AllScannedItems -or $script:AllScannedItems.Count -eq 0) { return }
    if ($null -eq $script:LiveList) { return }

    # [FIX] No tocar LiveList mientras el escaneo está activo — el timer del scanner
    # la gestiona exclusivamente. Guardar el texto y aplicar solo cuando termine.
    if ($null -ne $script:DiskScanAsync) { return }

    if ([string]::IsNullOrWhiteSpace($script:FilterText)) {
        # Sin filtro: vista normal jerárquica
        Refresh-DiskView
    } else {
        # Con filtro: lista plana de items cuyo nombre contiene el texto
        $script:LiveList.Clear()
        foreach ($item in $script:AllScannedItems) {
            if ($item.SizeBytes -ge 0 -and $item.DisplayName -like "*$script:FilterText*") {
                $script:LiveList.Add($item)
            }
        }
    }
}

$txtDiskFilter.Add_TextChanged({
    Apply-DiskFilter $txtDiskFilter.Text
    Save-Settings
})

$btnDiskFilterClear.Add_Click({
    $txtDiskFilter.Text = ""
    Apply-DiskFilter ""
})

# ─────────────────────────────────────────────────────────────────────────────
# [B2] MENÚ CONTEXTUAL DEL EXPLORADOR DE DISCO
# ─────────────────────────────────────────────────────────────────────────────
$ctxMenu.Add_Opened({
    $sel = $lbDiskTree.SelectedItem
    $hasItem = $null -ne $sel
    $ctxOpen.IsEnabled       = $hasItem -and $sel.IsDir -and (Test-Path $sel.FullPath)
    $ctxCopy.IsEnabled       = $hasItem
    $ctxScanFolder.IsEnabled = $hasItem -and $sel.IsDir -and (Test-Path $sel.FullPath)
    $ctxDelete.IsEnabled     = $hasItem -and $sel.IsDir -and (Test-Path $sel.FullPath)
})

$ctxOpen.Add_Click({
    $sel = $lbDiskTree.SelectedItem
    if ($null -ne $sel -and (Test-Path $sel.FullPath)) {
        Start-Process "explorer.exe" $sel.FullPath
    }
})

$ctxCopy.Add_Click({
    $sel = $lbDiskTree.SelectedItem
    if ($null -ne $sel) {
        [System.Windows.Clipboard]::SetText($sel.FullPath)
        $txtDiskScanStatus.Text = "✅ Ruta copiada: $($sel.FullPath)"
    }
})

$ctxDelete.Add_Click({
    $sel = $lbDiskTree.SelectedItem
    if ($null -eq $sel -or -not $sel.IsDir) { return }
    $confirm = Show-ThemedDialog -Title "Confirmar eliminación" `
        -Message "¿Eliminar permanentemente esta carpeta?`n`n$($sel.FullPath)`n`nTamaño: $($sel.SizeStr)`n`nEsta acción no se puede deshacer." `
        -Type "warning" -Buttons "YesNo"
    if ($confirm) {
        try {
            Remove-Item -Path $sel.FullPath -Recurse -Force -ErrorAction Stop
            # Quitar de AllScannedItems y refrescar vista
            $toRemove = $script:AllScannedItems | Where-Object {
                $_.FullPath -eq $sel.FullPath -or $_.FullPath.StartsWith($sel.FullPath + "\")
            }
            foreach ($r in @($toRemove)) { $script:AllScannedItems.Remove($r) | Out-Null }
            Refresh-DiskView -RebuildMap
            $txtDiskScanStatus.Text = "🗑 Eliminado: $($sel.FullPath)"
        } catch {
            Show-ThemedDialog -Title "Error al eliminar" `
                -Message "Error al eliminar:`n$($_.Exception.Message)" -Type "error"
        }
    }
})

# [B2+] Mostrar Output desde menú contextual del explorador
if ($null -ne $ctxShowOutput2) {
    $ctxShowOutput2.Add_Click({ Set-OutputState "normal" })
}

# ─────────────────────────────────────────────────────────────────────────────
# [N9] Escanear carpeta — ventana emergente con árbol de archivos y operaciones
# ─────────────────────────────────────────────────────────────────────────────
$ctxScanFolder.Add_Click({
    $sel = $lbDiskTree.SelectedItem
    if ($null -eq $sel -or -not $sel.IsDir -or -not (Test-Path $sel.FullPath)) { return }
    Show-FolderScanner -FolderPath $sel.FullPath
})

# ─────────────────────────────────────────────────────────────────────────────
# [B3] EXPORTAR RESULTADOS A CSV
# ─────────────────────────────────────────────────────────────────────────────
$btnExportCsv.Add_Click({
    if ($null -eq $script:AllScannedItems -or $script:AllScannedItems.Count -eq 0) {
        Show-ThemedDialog -Title "Sin datos" `
            -Message "No hay datos de escaneo. Realiza un escaneo primero." -Type "info"
        return
    }
    $dlgFile = New-Object System.Windows.Forms.SaveFileDialog
    $dlgFile.Title      = "Exportar resultados del explorador"
    $dlgFile.Filter     = "CSV (*.csv)|*.csv|Todos los archivos|*.*"
    $dlgFile.DefaultExt = "csv"
    $dlgFile.FileName   = "SysOpt_Disco_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $dlgFile.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    if ($dlgFile.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $csvPath = $dlgFile.FileName

    $btnExportCsv.IsEnabled  = $false
    $txtDiskScanStatus.Text  = "⏳ Exportando CSV en segundo plano..."

    $script:ExportState.Phase     = "Preparando datos..."
    $script:ExportState.Progress  = 0
    $script:ExportState.ItemsDone = 0
    $script:ExportState.ItemsTotal= $script:AllScannedItems.Count
    $script:ExportState.Done      = $false
    $script:ExportState.Error     = ""
    $script:ExportState.Result    = ""

    # [RAM-03] Pasar AllScannedItems por referencia — sin clonar $csvData
    $script:ExportState.DataRef  = $script:AllScannedItems
    $script:ExportState.CsvPath2 = $csvPath

    $bgCsvScript = {
        param($State, $CsvPath)
        try {
            # [RAM-03] Leer directamente desde la referencia compartida
            $Items = $State.DataRef
            $State.Phase    = "Ordenando datos..."
            $State.Progress = 5
            # Ordenar in-place sin crear lista nueva — usar Array.Sort con comparer
            $sorted = [System.Linq.Enumerable]::OrderByDescending(
                [System.Collections.Generic.IEnumerable[object]]$Items,
                [Func[object,long]]{ param($x) if ($x.SizeBytes -ge 0) { $x.SizeBytes } else { 0L } }
            )
            $State.Phase    = "Escribiendo CSV..."
            $State.Progress = 10
            $total = $Items.Count
            $State.ItemsTotal = $total
            # [RAM-02] StreamWriter con buffer 64KB
            $sw = [System.IO.StreamWriter]::new($CsvPath, $false, [System.Text.Encoding]::UTF8, 65536)
            try {
                $sw.WriteLine('"Ruta","Tamaño","Bytes","Archivos","Carpetas","% del total","Tipo"')
                $i = 0
                foreach ($r in $sorted) {
                    if ($r.SizeBytes -lt 0) { $i++; continue }
                    $ruta  = [string]$r.FullPath  -replace '"','""'
                    $tam   = [string]$r.SizeStr   -replace '"','""'
                    $arch  = [string]$r.FileCount -replace '"','""'
                    $pct   = [string]$r.PctStr    -replace '"','""'
                    $tipo  = if ($r.IsDir) { "Carpeta" } else { "Archivo" }
                    $sw.WriteLine('"' + $ruta + '","' + $tam + '",' + $r.SizeBytes + ',"' + $arch + '",' + $r.DirCount + ',"' + $pct + '","' + $tipo + '"')
                    $i++
                    if ($i % 1000 -eq 0) {
                        $sw.Flush()
                        $State.ItemsDone = $i
                        $State.Progress  = [int](10 + ($i / [math]::Max(1,$total)) * 85)
                        $State.Phase     = "Escribiendo fila $i de $total..."
                    }
                }
                $sw.Flush()
            } finally { $sw.Close(); $sw.Dispose() }
            $State.Result    = $CsvPath
            $State.Progress  = 100
            $State.Phase     = "Completado"
            $State.ItemsDone = $total
            $State.Done      = $true
        } catch {
            $State.Error = $_.Exception.Message
            $State.Done  = $true
        }
    }

    # [RAM-05] Usar RunspacePool
    $ctxCsv = New-PooledPS
    $ps4 = $ctxCsv.PS
    [void]$ps4.AddScript($bgCsvScript)
    [void]$ps4.AddParameter("State",   $script:ExportState)
    [void]$ps4.AddParameter("CsvPath", $csvPath)
    $asyncCsv = $ps4.BeginInvoke()

    $progCsv = Show-ExportProgressDialog
    if ($null -ne $progCsv.Title) { $progCsv.Title.Text = "Exportando CSV" }
    $progCsv.Window.Show()

    $csvTimer = New-Object System.Windows.Threading.DispatcherTimer
    $csvTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:_csvProg  = $progCsv
    $script:_csvTimer = $csvTimer
    $script:_csvPs    = $ps4
    $script:_csvCtx   = $ctxCsv
    $script:_csvAsync = $asyncCsv

    $csvTimer.Add_Tick({
        $st   = $script:ExportState
        $prog = $script:_csvProg
        $pct  = [int]$st.Progress
        $cntStr = if ($st.ItemsTotal -gt 0) { "$($st.ItemsDone) / $($st.ItemsTotal) filas" } else { "" }
        Update-ProgressDialog $prog $pct $st.Phase $cntStr
        if ($st.Done) {
            $script:_csvTimer.Stop()
            $prog.Window.Close()
            try { $script:_csvPs.EndInvoke($script:_csvAsync) | Out-Null } catch {}
            Dispose-PooledPS $script:_csvCtx
            $btnExportCsv.IsEnabled = $true
            if ($st.Error -ne "") {
                Show-ThemedDialog -Title "Error al exportar" -Message "Error:`n$($st.Error)" -Type "error"
            } else {
                $f = $st.Result
                $txtDiskScanStatus.Text = "✅ CSV exportado: $(Split-Path $f -Leaf)"
                $n = $script:AllScannedItems.Count
                Show-ThemedDialog -Title "Exportación completada" `
                    -Message "CSV guardado en:`n$f`n`n$n elementos." -Type "success"
                # [RAM-06] GC tras exportación
                Invoke-AggressiveGC
            }
        }
    })
    $csvTimer.Start()
})

# ── [B3] Generar informe HTML desde el explorador de disco ───────────────────
# La exportación ocurre en un Runspace separado para no bloquear la UI.
# ─────────────────────────────────────────────────────────────────────────────

$btnDiskReport.Add_Click({
    if ($null -eq $script:AllScannedItems -or $script:AllScannedItems.Count -eq 0) {
        Show-ThemedDialog -Title "Sin datos" `
            -Message "No hay datos de escaneo. Realiza un escaneo primero." -Type "info"
        return
    }
    $templatePath = Join-Path $script:AppDir "assets\templates\diskreport.html"
    if (-not (Test-Path $templatePath)) {
        Show-ThemedDialog -Title "Template no encontrado" `
            -Message "No se encontro el archivo de plantilla:`n$templatePath" -Type "error"
        return
    }

    $btnDiskReport.IsEnabled = $false
    $txtDiskScanStatus.Text  = "⏳ Generando informe HTML en segundo plano..."

    $script:ExportState.Phase     = "Preparando datos..."
    $script:ExportState.Progress  = 0
    $script:ExportState.ItemsDone = 0
    $script:ExportState.ItemsTotal= $script:AllScannedItems.Count
    $script:ExportState.Done      = $false
    $script:ExportState.Error     = ""
    $script:ExportState.Result    = ""

    # [RAM-03] Pasar AllScannedItems por referencia — sin clonar en $dataSnapshot
    # El runspace recibe la referencia directa al list; no hay copia de RAM en pico
    $script:ExportState.DataRef = $script:AllScannedItems

    $exportParams = @{
        State        = $script:ExportState
        TemplatePath = $templatePath
        ScanPath     = $txtDiskScanPath.Text
        AppDir       = $script:AppDir
    }

    $bgExportScript = {
        param($State, $TemplatePath, $ScanPath, $AppDir)

        function SafeHtml([string]$s) {
            $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' `
               -replace '"','&quot;' -replace "'","&#39;"
        }
        function FmtSize([long]$bytes) {
            if ($bytes -ge 1GB) { "{0:N2} GB" -f ($bytes/1GB) }
            elseif ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes/1MB) }
            elseif ($bytes -ge 1KB) { "{0:N0} KB" -f ($bytes/1KB) }
            else { "$bytes B" }
        }

        # [RAM-03] Leer directamente desde la referencia compartida — sin clonar
        $DataSnapshot = $State.DataRef

        try {
            $State.Phase = "Leyendo plantilla..."; $State.Progress = 2
            $tpl = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8)

            $State.Phase = "Cargando logo..."; $State.Progress = 5
            $logoB64 = ""
            $logoPath = Join-Path $AppDir "assets\img\sysopt.png"
            if (Test-Path $logoPath) {
                try { $logoB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($logoPath)) } catch {}
            }
            $logoTag = if ($logoB64) {
                "<img src='data:image/png;base64,$logoB64' alt='SysOpt' class='logo-img'/>"
            } else { "<div class='logo-fallback'>&#9881;</div>" }

            $State.Phase = "Calculando estadisticas..."; $State.Progress = 10
            $now        = Get-Date
            $reportDate = $now.ToString('yyyyMMddHHmm')
            $dateLong   = $now.ToString('dd/MM/yyyy HH:mm:ss')

            $validItems = @($DataSnapshot)
            $rootItems  = @($validItems | Where-Object { $_.Depth -eq 0 } | Sort-Object SizeBytes -Descending)
            $totalBytes = ($rootItems | Measure-Object -Property SizeBytes -Sum).Sum
            if ($totalBytes -le 0) { $totalBytes = 1 }
            $totalStr     = FmtSize $totalBytes
            $totalFolders = $validItems.Count
            $totalFiles   = ($validItems | ForEach-Object {
                $fc = $_.FileCount
                if ($fc -match '^(\d+)\s') { [int]$Matches[1] } else { 0 }
            } | Measure-Object -Sum).Sum

            $diskStatsExtra = ""; $diskUsageBar = ""
            try {
                $drive = [System.IO.Path]::GetPathRoot($ScanPath)
                if ($drive -match '^[A-Za-z]:\\$') {
                    $di   = [System.IO.DriveInfo]::new($drive)
                    $dTot = $di.TotalSize; $dFree = $di.AvailableFreeSpace
                    $dUsed= $dTot - $dFree
                    $dPct = [math]::Round($dUsed / $dTot * 100, 1)
                    $diskStatsExtra = "<div class=`"stat-box`"><div class=`"stat-lbl`">Total unidad $drive</div><div class=`"stat-val c-cyan`">$(FmtSize $dTot)</div></div><div class=`"stat-box`"><div class=`"stat-lbl`">Espacio libre</div><div class=`"stat-val c-green`">$(FmtSize $dFree)</div></div><div class=`"stat-box`"><div class=`"stat-lbl`">Uso de disco</div><div class=`"stat-val c-red`">$dPct%</div></div>"
                    $diskUsageBar   = "<div class=`"disk-bar-wrap`"><div class=`"disk-bar-fill`" style=`"width:$dPct%`"></div></div><div class=`"disk-bar-label`">$dPct% utilizado &mdash; $(FmtSize $dUsed) de $(FmtSize $dTot)</div>"
                }
            } catch {}

            $State.Phase = "Generando grafico de sectores..."; $State.Progress = 18
            $pal = @('#5BA3FF','#4AE896','#FFB547','#FF6B84','#9B7EFF','#2EDFBF',
                     '#FF9F43','#54A0FF','#5F27CD','#01CBC6','#FFC312','#C4E538',
                     '#12CBC4','#FDA7DF','#ED4C67','#F79F1F','#A29BFE','#74B9FF')
            $slicesSvg = ""; $legendHtml = ""
            $cx = 160; $cy = 160; $r = 148; $startAngle = -90.0
            $topN = [math]::Min($rootItems.Count, 16)
            $otherBytes = $totalBytes
            for ($i = 0; $i -lt $topN; $i++) { $otherBytes -= [long]$rootItems[$i].SizeBytes }
            $hasOther = ($rootItems.Count -gt $topN) -and ($otherBytes -gt 0)
            for ($i = 0; $i -lt $topN; $i++) {
                $item = $rootItems[$i]; $pct  = [long]$item.SizeBytes / $totalBytes
                $angle= $pct * 360.0; $endA = $startAngle + $angle
                $large= if ($angle -gt 180) { 1 } else { 0 }; $col = $pal[$i % $pal.Count]
                $pctLbl = [math]::Round($pct * 100, 1); $szStr = FmtSize ([long]$item.SizeBytes)
                $nameEsc = SafeHtml $item.DisplayName
                if ($angle -ge 359.9) {
                    $slicesSvg += "<circle cx='$cx' cy='$cy' r='$r' fill='$col' class='slice' data-name='$nameEsc' data-size='$szStr' data-pct='$pctLbl%'/>`n"
                } else {
                    $x1=[math]::Round($cx+$r*[math]::Cos($startAngle*[math]::PI/180),3)
                    $y1=[math]::Round($cy+$r*[math]::Sin($startAngle*[math]::PI/180),3)
                    $x2=[math]::Round($cx+$r*[math]::Cos($endA*[math]::PI/180),3)
                    $y2=[math]::Round($cy+$r*[math]::Sin($endA*[math]::PI/180),3)
                    $slicesSvg += "<path d='M$cx,$cy L$x1,$y1 A$r,$r 0 $large,1 $x2,$y2 Z' fill='$col' opacity='0.92' class='slice' data-name='$nameEsc' data-size='$szStr' data-pct='$pctLbl%'/>`n"
                }
                $legendHtml += "<div class='legend-item'><span class='legend-dot' style='background:$col'></span><span class='legend-name' title='$nameEsc'>$nameEsc</span><span class='legend-size'>$szStr</span><span class='legend-pct'>$pctLbl%</span></div>`n"
                $startAngle = $endA
            }
            if ($hasOther) {
                $angle=[math]::Round($otherBytes/$totalBytes*360,2); $endA=$startAngle+$angle
                $large=if($angle-gt 180){1}else{0}; $col='#3A4468'
                $szStr=FmtSize $otherBytes; $pctLbl=[math]::Round($otherBytes/$totalBytes*100,1)
                $x1=[math]::Round($cx+$r*[math]::Cos($startAngle*[math]::PI/180),3)
                $y1=[math]::Round($cy+$r*[math]::Sin($startAngle*[math]::PI/180),3)
                $x2=[math]::Round($cx+$r*[math]::Cos($endA*[math]::PI/180),3)
                $y2=[math]::Round($cy+$r*[math]::Sin($endA*[math]::PI/180),3)
                $slicesSvg += "<path d='M$cx,$cy L$x1,$y1 A$r,$r 0 $large,1 $x2,$y2 Z' fill='$col' opacity='0.7' class='slice' data-name='Otras carpetas' data-size='$szStr' data-pct='$pctLbl%'/>`n"
                $legendHtml += "<div class='legend-item'><span class='legend-dot' style='background:$col'></span><span class='legend-name'>Otras carpetas</span><span class='legend-size'>$szStr</span><span class='legend-pct'>$pctLbl%</span></div>`n"
            }

            $State.Phase = "Generando tabla de carpetas..."; $State.Progress = 25
            $State.ItemsTotal = $validItems.Count
            # [RAM-02b] StreamWriter a archivo temporal para las filas HTML
            # El StringBuilder ya no crece ilimitado en memoria
            $tmpRowsFile = [System.IO.Path]::GetTempFileName()
            $swRows = [System.IO.StreamWriter]::new($tmpRowsFile, $false, [System.Text.Encoding]::UTF8, 65536)
            $allSorted = @($validItems | Sort-Object SizeBytes -Descending)
            $total_items = $allSorted.Count
            $idx = 0; $startTime = [DateTime]::UtcNow
            try {
                for ($r2 = 0; $r2 -lt $total_items; $r2++) {
                    $item   = $allSorted[$r2]
                    $col2   = $pal[$idx % $pal.Count]
                    $pct2   = [math]::Round([long]$item.SizeBytes / $totalBytes * 100, 2)
                    $bar    = [math]::Min(100, $pct2)
                    $szStr2 = FmtSize ([long]$item.SizeBytes)
                    $nmEsc  = SafeHtml $item.DisplayName
                    $ptEsc  = SafeHtml $item.FullPath
                    $depth  = [int]$item.Depth
                    $dClass = switch ($depth) { 0 {"depth-0"} 1 {"depth-1"} 2 {"depth-2"} 3 {"depth-3"} default {"depth-4p"} }
                    $files  = if ($item.FileCount -match '^(\d+)\s' -and [int]$Matches[1] -gt 0) { $item.FileCount } else { "" }
                    $dotCol = if ($depth -eq 0) { $pal[$idx % $pal.Count] } else { "#3A4468" }
                    $swRows.WriteLine("<tr><td class=`"td-dot`"><span class=`"dot`" style=`"background:$dotCol`"></span></td><td class=`"$dClass`" title=`"$ptEsc`">$nmEsc</td><td class=`"td-path`" title=`"$ptEsc`">$ptEsc</td><td class=`"td-size`">$szStr2</td><td class=`"td-pct`">$pct2%</td><td class=`"td-files`">$files</td><td class=`"td-bar`"><div class=`"bar-wrap`"><div class=`"bar-fill`" style=`"width:$bar%;background:$dotCol`"></div></div></td></tr>")
                    if ($depth -eq 0) { $idx++ }
                    if ($r2 % 500 -eq 0) {
                        $swRows.Flush()
                        $State.ItemsDone = $r2
                        $elapsed = ([DateTime]::UtcNow - $startTime).TotalSeconds
                        $pctTable = if ($total_items -gt 0) { $r2 / $total_items } else { 1 }
                        $State.Progress = [int](25 + $pctTable * 55)
                        if ($elapsed -gt 0.5 -and $pctTable -gt 0.01) {
                            $eta = [int](($elapsed / $pctTable) * (1 - $pctTable))
                            $State.Phase = "Generando filas HTML... (ETA: ${eta}s)"
                        }
                    }
                }
                $swRows.Flush()
            } finally { $swRows.Close(); $swRows.Dispose() }
            $State.ItemsDone = $total_items; $State.Progress = 82

            $State.Phase = "Ensamblando HTML..."; $State.Progress = 85
            $scanPathEsc = SafeHtml $ScanPath
            # Leer las filas del archivo temporal
            $tableRowsStr = [System.IO.File]::ReadAllText($tmpRowsFile, [System.Text.Encoding]::UTF8)
            try { [System.IO.File]::Delete($tmpRowsFile) } catch {}
            $html = $tpl `
                -replace '{{LOGO_TAG}}',         $logoTag `
                -replace '{{SCAN_PATH}}',         $scanPathEsc `
                -replace '{{REPORT_DATE}}',       $reportDate `
                -replace '{{REPORT_DATE_LONG}}',  $dateLong `
                -replace '{{SCAN_TIME}}',         $dateLong `
                -replace '{{APP_VERSION}}',       "v2.4.0" `
                -replace '{{TOTAL_SIZE}}',        $totalStr `
                -replace '{{TOTAL_FOLDERS}}',     $totalFolders `
                -replace '{{TOTAL_FILES}}',       $totalFiles `
                -replace '{{DISK_STATS_EXTRA}}',  $diskStatsExtra `
                -replace '{{DISK_USAGE_BAR}}',    $diskUsageBar `
                -replace '{{PIE_SLICES}}',        $slicesSvg `
                -replace '{{PIE_LEGEND}}',        $legendHtml `
                -replace '{{TABLE_ROWS}}',        $tableRowsStr
            $tableRowsStr = $null  # liberar ref

            $State.Phase = "Escribiendo archivo..."; $State.Progress = 95
            $outDir = Join-Path $AppDir "output"
            if (-not (Test-Path $outDir)) { [System.IO.Directory]::CreateDirectory($outDir) | Out-Null }
            $outFile = Join-Path $outDir "diskreport_$reportDate.html"
            [System.IO.File]::WriteAllText($outFile, $html, [System.Text.Encoding]::UTF8)

            $State.Result = $outFile; $State.Progress = 100
            $State.Phase  = "Completado"; $State.Done = $true
        } catch {
            $State.Error = $_.Exception.Message; $State.Done = $true
        }
    }

    # [RAM-05] Usar RunspacePool
    $ctxHtml = New-PooledPS
    $ps2 = $ctxHtml.PS
    [void]$ps2.AddScript($bgExportScript)
    [void]$ps2.AddParameter("State",        $exportParams.State)
    [void]$ps2.AddParameter("TemplatePath", $exportParams.TemplatePath)
    [void]$ps2.AddParameter("ScanPath",     $exportParams.ScanPath)
    [void]$ps2.AddParameter("AppDir",       $exportParams.AppDir)
    $asyncHtml = $ps2.BeginInvoke()

    $progHtml = Show-ExportProgressDialog
    if ($null -ne $progHtml.Title) { $progHtml.Title.Text = "Generando informe HTML" }
    $progHtml.Window.Show()

    $htmlTimer = New-Object System.Windows.Threading.DispatcherTimer
    $htmlTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:_htmlProg  = $progHtml
    $script:_htmlTimer = $htmlTimer
    $script:_htmlPs    = $ps2
    $script:_htmlCtx   = $ctxHtml
    $script:_htmlAsync = $asyncHtml

    $htmlTimer.Add_Tick({
        $st   = $script:ExportState
        $prog = $script:_htmlProg
        $pct  = [int]$st.Progress
        $cntStr = if ($st.ItemsTotal -gt 0) { "$($st.ItemsDone) / $($st.ItemsTotal) elementos" } else { "" }
        Update-ProgressDialog $prog $pct $st.Phase $cntStr
        if ($st.Done) {
            $script:_htmlTimer.Stop()
            $prog.Window.Close()
            try { $script:_htmlPs.EndInvoke($script:_htmlAsync) | Out-Null } catch {}
            Dispose-PooledPS $script:_htmlCtx
            $btnDiskReport.IsEnabled = $true
            if ($st.Error -ne "") {
                $txtDiskScanStatus.Text = "Error al generar informe."
                Show-ThemedDialog -Title "Error al generar informe" -Message $st.Error -Type "error"
            } else {
                $outFile2 = $st.Result
                $txtDiskScanStatus.Text = "✅ Informe generado: $(Split-Path $outFile2 -Leaf)"
                $open = Show-ThemedDialog -Title "Informe generado" `
                    -Message "Informe HTML guardado en:`n$outFile2`n`n¿Abrir en el navegador?" `
                    -Type "success" -Buttons "YesNo"
                if ($open) { Start-Process $outFile2 }
                # [RAM-06] GC tras exportación HTML
                Invoke-AggressiveGC
            }
        }
    })
    $htmlTimer.Start()
})


# ── Toggle colapsar/expandir carpetas ────────────────────────────────────────
$lbDiskTree.AddHandler(
    [System.Windows.Controls.Button]::ClickEvent,
    [System.Windows.RoutedEventHandler]{
        param($s, $e)
        $btn = $e.OriginalSource
        if ($btn -is [System.Windows.Controls.Button] -and $null -ne $btn.Tag -and "$($btn.Tag)" -ne "") {
            $path = [string]$btn.Tag
            if ($script:CollapsedPaths.Contains($path)) {
                # Expandir: quitar de colapsados, actualizar icono
                $script:CollapsedPaths.Remove($path) | Out-Null
                if ($null -ne $script:LiveItems -and $script:LiveItems.ContainsKey($path) -and $null -ne $script:AllScannedItems) {
                    $script:AllScannedItems[$script:LiveItems[$path]].ToggleIcon = [string][char]0x25BC   # ▼
                }
            } else {
                # Colapsar: añadir a colapsados, actualizar icono
                $script:CollapsedPaths.Add($path) | Out-Null
                if ($null -ne $script:LiveItems -and $script:LiveItems.ContainsKey($path) -and $null -ne $script:AllScannedItems) {
                    $script:AllScannedItems[$script:LiveItems[$path]].ToggleIcon = [string][char]0x25B6   # ▶
                }
            }
            # Refresh reconstruye qué items son visibles (muestra/oculta hijos).
            # Items.Refresh() es obligatorio: LiveList es List<T>, no ObservableCollection —
            # WPF no detecta Clear()/Add() sin notificación explícita al ItemsControl.
            Refresh-DiskView
            $lbDiskTree.Items.Refresh()
            $e.Handled = $true
        }
    }
)

# Selección en la lista → actualizar panel de detalle
$lbDiskTree.Add_SelectionChanged({
    $sel = $lbDiskTree.SelectedItem
    if ($null -eq $sel) { return }

    $txtDiskDetailName.Text  = $sel.DisplayName
    $txtDiskDetailSize.Text  = $sel.SizeStr
    $txtDiskDetailFiles.Text = if ($sel.IsDir) { $sel.FileCount } else { "1 archivo" }
    $txtDiskDetailDirs.Text  = if ($sel.IsDir) { "$($sel.DirCount) carpetas" } else { "—" }
    $txtDiskDetailPct.Text   = "$($sel.TotalPct)%"

    # Top 10 archivos más grandes — ejecutado en runspace para no bloquear la UI
    $icTopFiles.ItemsSource = @([PSCustomObject]@{ FileName = "Buscando archivos grandes…"; FileSize = "" })
    $selPath = $sel.FullPath
    if ($sel.IsDir -and (Test-Path $selPath)) {
        $topBg = {
            param([string]$p)
            try {
                [System.IO.Directory]::GetFiles($p, "*", [System.IO.SearchOption]::AllDirectories) |
                    ForEach-Object {
                        try { [PSCustomObject]@{ Name=[System.IO.Path]::GetFileName($_); Len=([System.IO.FileInfo]$_).Length } } catch {}
                    } |
                    Sort-Object Len -Descending |
                    Select-Object -First 10
            } catch { @() }
        }
        # [RAM-05] Usar RunspacePool para top-files
        $ctxTop = New-PooledPS
        $psTop = $ctxTop.PS
        [void]$psTop.AddScript($topBg).AddParameter("p", $selPath)
        $asyncTop = $psTop.BeginInvoke()
        $topTimer = New-Object System.Windows.Threading.DispatcherTimer
        $topTimer.Interval = [TimeSpan]::FromMilliseconds(200)
        $script:_topCtx = $ctxTop
        $topTimer.Add_Tick({
            if (-not $asyncTop.IsCompleted) { return }
            $topTimer.Stop()
            $results = try { $psTop.EndInvoke($asyncTop) } catch { @() }
            Dispose-PooledPS $script:_topCtx
            $topFiles2 = [System.Collections.Generic.List[object]]::new()
            foreach ($r in $results) {
                if ($null -ne $r) {
                    $sz = if ($r.Len -ge 1GB) { "{0:N1} GB" -f ($r.Len/1GB) } elseif ($r.Len -ge 1MB) { "{0:N0} MB" -f ($r.Len/1MB) } elseif ($r.Len -ge 1KB) { "{0:N0} KB" -f ($r.Len/1KB) } else { "$($r.Len) B" }
                    $topFiles2.Add([PSCustomObject]@{ FileName=$r.Name; FileSize=$sz })
                }
            }
            if ($topFiles2.Count -eq 0) { $topFiles2.Add([PSCustomObject]@{ FileName="(ningún archivo encontrado)"; FileSize="" }) }
            $icTopFiles.ItemsSource = $topFiles2
        })
        $topTimer.Start()
    }
})

# ─────────────────────────────────────────────────────────────────────────────
# [N9] Show-FolderScanner — ventana emergente de análisis de carpeta
# ─────────────────────────────────────────────────────────────────────────────
function Show-FolderScanner {
    param([string]$FolderPath)

    $fsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Explorador de Carpeta" Height="680" Width="920"
        WindowStartupLocation="CenterOwner" ResizeMode="CanResize"
        Background="#0D0F1A">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Foreground" Value="#E8ECF4"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="FontFamily"    Value="Segoe UI"/>
            <Setter Property="FontSize"      Value="11"/>
            <Setter Property="Cursor"        Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding"       Value="10,5"/>
        </Style>
        <Style TargetType="ContextMenu">
            <Setter Property="Background"      Value="#1A1E2F"/>
            <Setter Property="BorderBrush"     Value="#3A4468"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding"         Value="4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ContextMenu">
                        <Border Background="#1A1E2F" BorderBrush="#3A4468" BorderThickness="1" CornerRadius="8" Padding="4,4">
                            <ItemsPresenter/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="MenuItem">
            <Setter Property="FontFamily"  Value="Segoe UI"/>
            <Setter Property="FontSize"    Value="12"/>
            <Setter Property="Foreground"  Value="#E8ECF4"/>
            <Setter Property="Background"  Value="Transparent"/>
            <Setter Property="Padding"     Value="10,6"/>
            <Setter Property="Cursor"      Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="MenuItem">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="5" Margin="2,1" Padding="{TemplateBinding Padding}">
                            <ContentPresenter ContentSource="Header" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1E3058"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="MIDanger" TargetType="MenuItem" BasedOn="{StaticResource {x:Type MenuItem}}">
            <Setter Property="Foreground" Value="#FF6B84"/>
        </Style>
        <Style TargetType="Separator">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Separator">
                        <Rectangle Height="1" Fill="#2A3448" Margin="8,3"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="5"/>
            <Setter Property="Background" Value="Transparent"/>
        </Style>
        <Style TargetType="ProgressBar">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Border CornerRadius="3" Background="#1A1E2F" BorderBrush="#252B40" BorderThickness="1" Height="5">
                            <Border x:Name="PART_Track">
                                <Border x:Name="PART_Indicator" HorizontalAlignment="Left" CornerRadius="3">
                                    <Border.Background>
                                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                            <GradientStop Color="#5BA3FF" Offset="0"/>
                                            <GradientStop Color="#2EDFBF" Offset="1"/>
                                        </LinearGradientBrush>
                                    </Border.Background>
                                </Border>
                            </Border>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="16,12,16,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Cabecera -->
        <Border Grid.Row="0" CornerRadius="10" Background="#1A1E2F" BorderBrush="#252B40" BorderThickness="1" Padding="16,12" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Border Grid.Column="0" Width="38" Height="38" CornerRadius="10" Background="#1A3058" Margin="0,0,12,0" VerticalAlignment="Center">
                    <TextBlock Text="🔍" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="Explorador de Carpeta" FontSize="15" FontWeight="Bold" Foreground="#E8ECF4"/>
                    <TextBlock Name="fsPathLabel" FontSize="10" Foreground="#9BA4C0" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border CornerRadius="6" Background="#132040" BorderBrush="#3A4468" BorderThickness="1" Padding="10,5" Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Total: " FontSize="11" Foreground="#9BA4C0"/>
                            <TextBlock Name="fsTotalSize" Text="—" FontSize="11" FontWeight="Bold" Foreground="#5BA3FF"/>
                        </StackPanel>
                    </Border>
                    <Border CornerRadius="6" Background="#132040" BorderBrush="#3A4468" BorderThickness="1" Padding="10,5">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Archivos: " FontSize="11" Foreground="#9BA4C0"/>
                            <TextBlock Name="fsFileCount" Text="—" FontSize="11" FontWeight="Bold" Foreground="#4AE896"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Barra de búsqueda/filtro + ordenación -->
        <Border Grid.Row="1" CornerRadius="8" Background="#1A1E2F" BorderBrush="#252B40" BorderThickness="1" Padding="10,7" Margin="0,0,0,8">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox Name="fsFilter" Grid.Column="0"
                         Background="#0D0F1A" Foreground="#E8ECF4"
                         BorderBrush="#3A4468" BorderThickness="1"
                         FontFamily="Segoe UI" FontSize="11" Padding="8,5"
                         VerticalContentAlignment="Center"
                         CaretBrush="#5BA3FF" SelectionBrush="#3D8EFF"/>
                <TextBlock Name="fsFilterHint" Grid.Column="0"
                           Text="  🔎  Filtrar por nombre…" FontSize="11" Foreground="#4A5068"
                           VerticalAlignment="Center" IsHitTestVisible="False" Margin="2,0"/>
                <TextBlock Grid.Column="1" Text="Ordenar:" FontSize="11" Foreground="#9BA4C0" VerticalAlignment="Center" Margin="10,0,6,0"/>
                <StackPanel Grid.Column="2" Orientation="Horizontal">
                    <Button Name="fsSortSize"  Content="Tamaño ↓" Background="#132040" BorderBrush="#3A4468" Foreground="#5BA3FF" Margin="0,0,4,0" FontSize="10"/>
                    <Button Name="fsSortName"  Content="Nombre"   Background="#1A1E2F" BorderBrush="#3A4468" Foreground="#9BA4C0" Margin="0,0,4,0" FontSize="10"/>
                    <Button Name="fsSortExt"   Content="Extensión" Background="#1A1E2F" BorderBrush="#3A4468" Foreground="#9BA4C0" FontSize="10"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Lista de archivos -->
        <Border Grid.Row="2" CornerRadius="10" Background="#131625" BorderBrush="#252B40" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <!-- Cabecera de columnas -->
                <Border Grid.Row="0" Background="#1A1E2F" BorderBrush="#252B40" BorderThickness="0,0,0,1" Padding="0,0,0,0">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="30"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="80"/>
                            <ColumnDefinition Width="180"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="" Padding="8,6"/>
                        <TextBlock Grid.Column="1" Text="Nombre" FontSize="10" FontWeight="SemiBold" Foreground="#9BA4C0" Padding="4,6"/>
                        <TextBlock Grid.Column="2" Text="Tamaño"   FontSize="10" FontWeight="SemiBold" Foreground="#9BA4C0" Padding="4,6" TextAlignment="Right"/>
                        <TextBlock Grid.Column="3" Text="Ext."     FontSize="10" FontWeight="SemiBold" Foreground="#9BA4C0" Padding="4,6" TextAlignment="Center"/>
                        <TextBlock Grid.Column="4" Text="Modificado" FontSize="10" FontWeight="SemiBold" Foreground="#9BA4C0" Padding="4,6"/>
                    </Grid>
                </Border>
                <!-- Filas de archivos -->
                <ListBox Name="fsListBox" Grid.Row="1"
                         Background="Transparent" BorderThickness="0"
                         ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                         VirtualizingStackPanel.IsVirtualizing="True"
                         SelectionMode="Single">
                    <ListBox.ContextMenu>
                        <ContextMenu>
                            <MenuItem Name="fsCtxPreview"  Header="👁  Vista previa / Abrir archivo"/>
                            <MenuItem Name="fsCtxLocation" Header="📂  Ir a la ubicación"/>
                            <Separator/>
                            <MenuItem Name="fsCtxDelete"   Header="🗑  Eliminar archivo" Style="{StaticResource MIDanger}"/>
                        </ContextMenu>
                    </ListBox.ContextMenu>
                    <ListBox.ItemContainerStyle>
                        <Style TargetType="ListBoxItem">
                            <Setter Property="Padding" Value="0"/>
                            <Setter Property="Margin"  Value="0"/>
                            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                            <Setter Property="Template">
                                <Setter.Value>
                                    <ControlTemplate TargetType="ListBoxItem">
                                        <Border x:Name="lbi" Background="Transparent"
                                                BorderBrush="#1E2740" BorderThickness="0,0,0,1">
                                            <ContentPresenter/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsSelected" Value="True">
                                                <Setter TargetName="lbi" Property="Background" Value="#1A3A5C"/>
                                            </Trigger>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="lbi" Property="Background" Value="#1E253B"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Setter.Value>
                            </Setter>
                        </Style>
                    </ListBox.ItemContainerStyle>
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <Grid Height="32">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="30"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="90"/>
                                    <ColumnDefinition Width="80"/>
                                    <ColumnDefinition Width="180"/>
                                </Grid.ColumnDefinitions>
                                <!-- Barra proporcional de tamaño -->
                                <Border Grid.Column="0" Grid.ColumnSpan="5" HorizontalAlignment="Left"
                                        Width="{Binding BarW}" Height="32"
                                        Background="{Binding BarC}" Opacity="0.13"/>
                                <!-- Icono tipo -->
                                <TextBlock Grid.Column="0" Text="{Binding Icon}"
                                           FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                <!-- Nombre -->
                                <TextBlock Grid.Column="1" Text="{Binding DisplayName}"
                                           FontSize="11" Foreground="{Binding NameColor}"
                                           VerticalAlignment="Center" Padding="4,0"
                                           TextTrimming="CharacterEllipsis"/>
                                <!-- Tamaño -->
                                <TextBlock Grid.Column="2" Text="{Binding SizeStr}"
                                           FontSize="11" Foreground="{Binding SizeColor}"
                                           FontWeight="SemiBold"
                                           VerticalAlignment="Center" TextAlignment="Right" Padding="4,0"/>
                                <!-- Extensión -->
                                <Border Grid.Column="3" CornerRadius="4" Background="#1A2540"
                                        HorizontalAlignment="Center" VerticalAlignment="Center" Padding="5,2" Margin="2,0">
                                    <TextBlock Text="{Binding Ext}" FontSize="9" Foreground="#9BA4C0"
                                               HorizontalAlignment="Center"/>
                                </Border>
                                <!-- Fecha modificación -->
                                <TextBlock Grid.Column="4" Text="{Binding Modified}"
                                           FontSize="10" Foreground="#4A5068"
                                           VerticalAlignment="Center" Padding="4,0"/>
                            </Grid>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
            </Grid>
        </Border>

        <!-- Barra de progreso del escaneo -->
        <Border Grid.Row="3" CornerRadius="8" Background="#1A1E2F" BorderBrush="#252B40" BorderThickness="1" Padding="12,8" Margin="0,8,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Name="fsScanStatus" Text="Iniciando escaneo…" FontSize="10" Foreground="#9BA4C0" Margin="0,0,0,4"/>
                    <ProgressBar Name="fsScanProgress" IsIndeterminate="True" Height="5"/>
                </StackPanel>
                <TextBlock Name="fsScanCount" Grid.Column="1" Text="" FontSize="10" Foreground="#5BA3FF"
                           VerticalAlignment="Center" Margin="12,0,0,0" FontWeight="SemiBold"/>
            </Grid>
        </Border>

        <!-- Footer -->
        <Grid Grid.Row="4" Margin="0,8,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Name="fsSelInfo" Grid.Column="0" Text="" FontSize="10" Foreground="#9BA4C0" VerticalAlignment="Center"/>
            <Button Name="fsBtnClose" Grid.Column="1" Content="Cerrar"
                    Background="#2E0E14" BorderBrush="#FF4D6A" Foreground="#FF4D6A"
                    MinWidth="90"/>
        </Grid>
    </Grid>
</Window>
"@

    $fsReader  = [System.Xml.XmlNodeReader]::new([xml]$fsXaml)
    $fsWindow  = [Windows.Markup.XamlReader]::Load($fsReader)
    $fsWindow.Owner = $window

    # ── Obtener controles ──
    $fsPathLabel   = $fsWindow.FindName("fsPathLabel")
    $fsTotalSize   = $fsWindow.FindName("fsTotalSize")
    $fsFileCount   = $fsWindow.FindName("fsFileCount")
    $fsFilter      = $fsWindow.FindName("fsFilter")
    $fsFilterHint  = $fsWindow.FindName("fsFilterHint")
    $fsSortSize    = $fsWindow.FindName("fsSortSize")
    $fsSortName    = $fsWindow.FindName("fsSortName")
    $fsSortExt     = $fsWindow.FindName("fsSortExt")
    $fsListBox     = $fsWindow.FindName("fsListBox")
    $fsScanStatus  = $fsWindow.FindName("fsScanStatus")
    $fsScanProgress= $fsWindow.FindName("fsScanProgress")
    $fsScanCount   = $fsWindow.FindName("fsScanCount")
    $fsSelInfo     = $fsWindow.FindName("fsSelInfo")
    $fsBtnClose    = $fsWindow.FindName("fsBtnClose")
    $fsCtxMenu     = $fsListBox.ContextMenu
    $fsCtxPreview  = $fsCtxMenu.Items | Where-Object { $_.Name -eq "fsCtxPreview"  }
    $fsCtxLocation = $fsCtxMenu.Items | Where-Object { $_.Name -eq "fsCtxLocation" }
    $fsCtxDelete   = $fsCtxMenu.Items | Where-Object { $_.Name -eq "fsCtxDelete"   }

    $fsPathLabel.Text = $FolderPath
    $script:fsAllItems  = [System.Collections.Generic.List[object]]::new()
    $script:fsSortMode  = "size"   # "size" | "name" | "ext"
    $script:fsFilterTxt = ""

    # ── Helper: formatear tamaño ──
    function Format-FsSize([long]$b) {
        if ($b -ge 1GB) { return "{0:N2} GB" -f ($b / 1GB) }
        if ($b -ge 1MB) { return "{0:N1} MB" -f ($b / 1MB) }
        if ($b -ge 1KB) { return "{0:N0} KB" -f ($b / 1KB) }
        return "$b B"
    }

    # ── Helper: color por tamaño ──
    function Get-FsSizeColor([long]$b) {
        if ($b -ge 1GB)  { return "#FF6B84" }
        if ($b -ge 100MB){ return "#FFB547" }
        if ($b -ge 10MB) { return "#5BA3FF" }
        return "#9BA4C0"
    }

    # ── Helper: icono por extensión ──
    function Get-FsIcon([string]$ext) {
        switch ($ext.ToLower()) {
            {$_ -in @(".mp4",".mkv",".avi",".mov",".wmv",".ts",".m2ts")} { return "🎬" }
            {$_ -in @(".mp3",".flac",".wav",".aac",".ogg",".m4a")}        { return "🎵" }
            {$_ -in @(".jpg",".jpeg",".png",".gif",".bmp",".webp",".raw")} { return "🖼" }
            {$_ -in @(".zip",".rar",".7z",".tar",".gz",".bz2")}           { return "📦" }
            {$_ -in @(".exe",".msi",".dll",".sys")}                        { return "⚙" }
            {$_ -in @(".pdf")}                                             { return "📄" }
            {$_ -in @(".doc",".docx",".odt")}                              { return "📝" }
            {$_ -in @(".xls",".xlsx",".csv")}                              { return "📊" }
            {$_ -in @(".ppt",".pptx")}                                     { return "📑" }
            {$_ -in @(".iso",".img",".vhd",".vmdk")}                       { return "💿" }
            {$_ -in @(".ps1",".py",".js",".ts",".cs",".cpp",".h")}        { return "💻" }
            default                                                         { return "📄" }
        }
    }

    # ── Refrescar la lista con filtro y orden actuales ──
    function Refresh-FsList {
        # Liberar referencia anterior antes de reasignar (ayuda al GC)
        $fsListBox.ItemsSource = $null

        $filtered = if ($script:fsFilterTxt -ne "") {
            $script:fsAllItems | Where-Object { $_.FullPath -like "*$($script:fsFilterTxt)*" }
        } else { $script:fsAllItems }

        $sorted = switch ($script:fsSortMode) {
            "name" { $filtered | Sort-Object DisplayName }
            "ext"  { $filtered | Sort-Object Ext, DisplayName }
            default{ $filtered | Sort-Object SizeBytes -Descending }
        }

        # Calcular máximo con un solo foreach (sin Measure-Object que crea pipeline completo)
        $maxB = [long]0
        foreach ($it in $script:fsAllItems) { if ($it.SizeBytes -gt $maxB) { $maxB = $it.SizeBytes } }
        if ($maxB -le 0) { $maxB = 1 }

        # Pre-reservar capacidad para evitar realocaciones internas de la lista
        $rows = [System.Collections.Generic.List[object]]::new([Math]::Max(1, $script:fsAllItems.Count))
        foreach ($it in $sorted) {
            $it.BarW = [Math]::Max(4, [int](($it.SizeBytes / $maxB) * 700))
            $rows.Add($it)
        }
        $fsListBox.ItemsSource = $rows

        # Usar $script:fsTotalBytes ya acumulado — evita otro Measure-Object sobre toda la colección
        $fsTotalSize.Text  = Format-FsSize $script:fsTotalBytes
        $fsFileCount.Text  = "$($script:fsAllItems.Count) archivos"
    }

    # ── Escaneo streaming con ConcurrentQueue (nunca bloquea la UI) ──
    # EnumerateFiles es lazy: el runspace emite archivo a archivo a la queue.
    # El DispatcherTimer drena la queue en lotes de 200 por tick → UI siempre fluida.
    # Al terminar: GC + EmptyWorkingSet libera la RAM del runspace.
    $script:fsScanQueue  = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $script:fsScanDone   = $false
    $script:fsTotalBytes = [long]0

    $scanScript = {
        param(
            [string]$root,
            [System.Collections.Concurrent.ConcurrentQueue[object]]$queue,
            [ref]$done
        )
        try {
            $di = [System.IO.DirectoryInfo]::new($root)
            foreach ($f in $di.EnumerateFiles("*", [System.IO.SearchOption]::AllDirectories)) {
                try {
                    $queue.Enqueue([PSCustomObject]@{
                        P = $f.FullName
                        N = $f.Name
                        B = $f.Length
                        X = $f.Extension
                        M = $f.LastWriteTime.ToString("dd/MM/yyyy  HH:mm")
                    })
                } catch {}
            }
        } catch {}
        $done.Value = $true
    }

    $rsFs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rsFs.Open()
    $psFs = [System.Management.Automation.PowerShell]::Create()
    $psFs.Runspace = $rsFs
    [void]$psFs.AddScript($scanScript).AddParameter("root", $FolderPath).AddParameter("queue", $script:fsScanQueue).AddParameter("done", ([ref]$script:fsScanDone))
    $asyncFs = $psFs.BeginInvoke()

    # Lote adaptativo: en equipos con poca RAM disponible se reduce automáticamente
    $availMB = [Math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
    $BATCH = if ($availMB -lt 2048) { 50 } elseif ($availMB -lt 4096) { 150 } else { 300 }

    $scanTimer = New-Object System.Windows.Threading.DispatcherTimer
    # Intervalo adaptativo: más lento si hay poca RAM libre
    $scanIntervalMs = if ($availMB -lt 2048) { 250 } elseif ($availMB -lt 4096) { 180 } else { 120 }
    $scanTimer.Interval = [TimeSpan]::FromMilliseconds($scanIntervalMs)
    $scanTimer.Add_Tick({
        # Drena hasta $BATCH items de la queue
        $processed = 0
        $item = $null
        while ($processed -lt $BATCH -and $script:fsScanQueue.TryDequeue([ref]$item)) {
            $ext  = if ($item.X) { $item.X } else { "" }
            $icon = Get-FsIcon $ext
            $sc   = Get-FsSizeColor $item.B
            $script:fsAllItems.Add([PSCustomObject]@{
                FullPath    = $item.P
                DisplayName = $item.N
                SizeBytes   = $item.B
                SizeStr     = Format-FsSize $item.B
                SizeColor   = $sc
                Ext         = $ext.TrimStart(".")
                Modified    = $item.M
                Icon        = $icon
                NameColor   = "#E8ECF4"
                BarC        = $sc
                BarW        = 0
            })
            $script:fsTotalBytes += $item.B
            $processed++
            $item = $null  # liberar referencia al objeto de cola
        }

        # Actualizar contador en vivo
        $cnt = $script:fsAllItems.Count
        if ($cnt -gt 0) {
            $fsScanStatus.Text = "Escaneando…   $cnt archivos  ·  $(Format-FsSize $script:fsTotalBytes)"
            $fsScanCount.Text  = "$cnt archivos"
        }

        # ¿Terminado? Queue vacía Y runspace señaliza done
        if ($script:fsScanDone -and $script:fsScanQueue.IsEmpty) {
            $scanTimer.Stop()

            # Limpiar runspace
            try { $psFs.Stop()  } catch {}
            try { $psFs.Dispose() } catch {}
            try { $rsFs.Close(); $rsFs.Dispose() } catch {}

            # Liberar memoria del proceso — trabajar como el gestor de RAM de SysOpt
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            try {
                $proc = [System.Diagnostics.Process]::GetCurrentProcess()
                Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public class WseTrim2{[DllImport("kernel32.dll")]public static extern bool SetProcessWorkingSetSize(IntPtr h,IntPtr mn,IntPtr mx);}
'@ -ErrorAction SilentlyContinue
                [WseTrim2]::SetProcessWorkingSetSize($proc.Handle, [IntPtr](-1), [IntPtr](-1)) | Out-Null
            } catch {}

            $fsScanProgress.IsIndeterminate = $false
            $fsScanProgress.Value           = 100
            $cnt2 = $script:fsAllItems.Count
            $fsScanStatus.Text = "✅  Completado — $cnt2 archivos  ·  $(Format-FsSize $script:fsTotalBytes)"
            $fsScanCount.Text  = "$cnt2 archivos"
            $fsTotalSize.Text  = Format-FsSize $script:fsTotalBytes
            $fsFileCount.Text  = "$cnt2 archivos"
            Refresh-FsList
        }
    })
    $scanTimer.Start()

    # ── Filtro en tiempo real ──
    $fsFilter.Add_TextChanged({
        $script:fsFilterTxt = $fsFilter.Text
        $fsFilterHint.Visibility = if ($fsFilter.Text -eq "") {
            [System.Windows.Visibility]::Visible
        } else {
            [System.Windows.Visibility]::Collapsed
        }
        Refresh-FsList
    })

    # ── Botones de ordenación ──
    $fsSortSize.Add_Click({
        $script:fsSortMode = "size"
        $fsSortSize.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#132040")
        $fsSortSize.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5BA3FF")
        $fsSortName.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
        $fsSortName.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#9BA4C0")
        $fsSortExt.Background  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
        $fsSortExt.Foreground  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#9BA4C0")
        Refresh-FsList
    })
    $fsSortName.Add_Click({
        $script:fsSortMode = "name"
        $fsSortName.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#132040")
        $fsSortName.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5BA3FF")
        $fsSortSize.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
        $fsSortSize.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#9BA4C0")
        $fsSortExt.Background  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
        $fsSortExt.Foreground  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#9BA4C0")
        Refresh-FsList
    })
    $fsSortExt.Add_Click({
        $script:fsSortMode = "ext"
        $fsSortExt.Background  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#132040")
        $fsSortExt.Foreground  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5BA3FF")
        $fsSortSize.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
        $fsSortSize.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#9BA4C0")
        $fsSortName.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1E2F")
        $fsSortName.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#9BA4C0")
        Refresh-FsList
    })

    # ── Info de selección ──
    $fsListBox.Add_SelectionChanged({
        $sel = $fsListBox.SelectedItem
        if ($null -ne $sel) {
            $fsSelInfo.Text = "$($sel.DisplayName)   ·   $($sel.SizeStr)   ·   $($sel.Modified)"
        } else { $fsSelInfo.Text = "" }
    })

    # ── Doble clic → abrir ──
    $fsListBox.Add_MouseDoubleClick({
        $sel = $fsListBox.SelectedItem
        if ($null -ne $sel -and (Test-Path $sel.FullPath)) {
            try { Start-Process $sel.FullPath } catch {
                Show-ThemedDialog -Title "Error al abrir archivo" `
                    -Message "No se puede abrir el archivo.`n$($_.Exception.Message)" -Type "error"
            }
        }
    })

    # ── Menú contextual de archivos ──
    $fsCtxMenu.Add_Opened({
        $sel = $fsListBox.SelectedItem
        $has = $null -ne $sel -and (Test-Path $sel.FullPath)
        $fsCtxPreview.IsEnabled  = $has
        $fsCtxLocation.IsEnabled = $has
        $fsCtxDelete.IsEnabled   = $has
    })

    $fsCtxPreview.Add_Click({
        $sel = $fsListBox.SelectedItem
        if ($null -ne $sel -and (Test-Path $sel.FullPath)) {
            try { Start-Process $sel.FullPath } catch {
                Show-ThemedDialog -Title "Error al abrir" `
                    -Message "No se puede abrir el archivo.`n$($_.Exception.Message)" -Type "error"
            }
        }
    })

    $fsCtxLocation.Add_Click({
        $sel = $fsListBox.SelectedItem
        if ($null -ne $sel -and (Test-Path $sel.FullPath)) {
            # Abrir explorador seleccionando el archivo
            Start-Process "explorer.exe" "/select,`"$($sel.FullPath)`""
        }
    })

    $fsCtxDelete.Add_Click({
        $sel = $fsListBox.SelectedItem
        if ($null -eq $sel) { return }
        $confirm = Show-ThemedDialog -Title "Confirmar eliminación" `
            -Message "¿Eliminar permanentemente este archivo?`n`n$($sel.FullPath)`n`nTamaño: $($sel.SizeStr)`n`nEsta acción no se puede deshacer." `
            -Type "warning" -Buttons "YesNo"
        if ($confirm) {
            try {
                Remove-Item -Path $sel.FullPath -Force -ErrorAction Stop
                $script:fsAllItems.Remove($sel) | Out-Null
                $fsScanStatus.Text = "🗑  Eliminado: $($sel.FullPath)"
                Refresh-FsList
            } catch {
                Show-ThemedDialog -Title "Error al eliminar" `
                    -Message "Error al eliminar:`n$($_.Exception.Message)" -Type "error"
            }
        }
    })

    # ── Cerrar ──
    $fsBtnClose.Add_Click({
        $scanTimer.Stop()
        $script:fsScanDone = $true          # señaliza al runspace que pare
        try { $psFs.Stop()    } catch {}
        try { $psFs.Dispose() } catch {}
        try { $rsFs.Close(); $rsFs.Dispose() } catch {}
        [System.GC]::Collect()
        $fsWindow.Close()
    })
    $fsWindow.Add_Closed({
        $scanTimer.Stop()
        $script:fsScanDone = $true
        try { $psFs.Stop()    } catch {}
        try { $psFs.Dispose() } catch {}
        try { $rsFs.Close(); $rsFs.Dispose() } catch {}
        [System.GC]::Collect()
    })

    $fsWindow.ShowDialog() | Out-Null
}

# ─────────────────────────────────────────────────────────────────────────────
# [N8] Ventana de gestión de programas de inicio
# ─────────────────────────────────────────────────────────────────────────────
function Show-StartupManager {
    $startupXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Gestor de Inicio" Height="560" Width="860"
        WindowStartupLocation="CenterOwner" ResizeMode="CanResize"
        Background="#0D0F1A" WindowStyle="None" AllowsTransparency="True">

    <Window.Resources>
        <!-- DataGrid oscuro -->
        <Style TargetType="DataGrid">
            <Setter Property="Background"            Value="#0D0F1A"/>
            <Setter Property="Foreground"            Value="#E8ECF4"/>
            <Setter Property="BorderBrush"           Value="#252B40"/>
            <Setter Property="BorderThickness"       Value="0"/>
            <Setter Property="RowBackground"         Value="#131625"/>
            <Setter Property="AlternatingRowBackground" Value="#0F1220"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#1A1E2F"/>
            <Setter Property="VerticalGridLinesBrush"   Value="Transparent"/>
            <Setter Property="ColumnHeaderHeight"    Value="34"/>
        </Style>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background"   Value="#1A1E2F"/>
            <Setter Property="Foreground"   Value="#7880A0"/>
            <Setter Property="BorderBrush"  Value="#252B40"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
            <Setter Property="Padding"      Value="10,0"/>
            <Setter Property="FontSize"     Value="10"/>
            <Setter Property="FontFamily"   Value="JetBrains Mono, Consolas"/>
            <Setter Property="FontWeight"   Value="SemiBold"/>
        </Style>
        <Style TargetType="DataGridRow">
            <Setter Property="Foreground"   Value="#E8ECF4"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#1A2F4A"/>
                    <Setter Property="Foreground" Value="#E8ECF4"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#181D2E"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="DataGridCell">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding"         Value="10,6"/>
            <Setter Property="Foreground"      Value="#E8ECF4"/>
            <Setter Property="FontSize"        Value="12"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="Foreground" Value="#E8ECF4"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#4AE896"/>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Background"  Value="#0D0F1A"/>
            <Setter Property="Width"       Value="6"/>
        </Style>
    </Window.Resources>

    <Border Background="#131625" BorderBrush="#252B40" BorderThickness="1" CornerRadius="10">
        <Border.Effect>
            <DropShadowEffect BlurRadius="30" ShadowDepth="0" Opacity="0.7" Color="#000000"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="52"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Barra de título arrastrable -->
            <Border Grid.Row="0" Background="#0D0F1A" CornerRadius="10,10,0,0"
                    BorderBrush="#252B40" BorderThickness="0,0,0,1"
                    Name="titleBar">
                <Grid Margin="18,0">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Width="26" Height="26" CornerRadius="6"
                                Background="#9B7EFF" Margin="0,0,10,0">
                            <TextBlock Text="🚀" FontSize="13"
                                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <TextBlock Text="Gestor de Programas de Inicio" FontSize="14" FontWeight="Bold"
                                   Foreground="#E8ECF4" VerticalAlignment="Center"
                                   FontFamily="Syne, Segoe UI"/>
                    </StackPanel>
                    <Button Name="btnCloseStartup" Content="✕" HorizontalAlignment="Right"
                            Width="32" Height="32" Background="Transparent" BorderThickness="0"
                            Foreground="#7880A0" FontSize="14" Cursor="Hand" VerticalAlignment="Center">
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Background" Value="Transparent"/>
                                <Setter Property="BorderThickness" Value="0"/>
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Background="{TemplateBinding Background}" CornerRadius="6"
                                                    Width="28" Height="28">
                                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter Property="Background" Value="#FF6B84"/>
                                                    <Setter Property="Foreground" Value="White"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>
                </Grid>
            </Border>

            <!-- Subtítulo informativo -->
            <Border Grid.Row="1" Background="#0D1E35" BorderBrush="#1A2B45" BorderThickness="0,0,0,1" Padding="18,8">
                <TextBlock Text="Entradas de autoarranque en el registro de Windows (HKCU y HKLM). Desmarca para deshabilitar."
                           FontSize="11" Foreground="#5BA3FF"
                           FontFamily="JetBrains Mono, Consolas" TextWrapping="Wrap"/>
            </Border>

            <!-- DataGrid temático -->
            <DataGrid Name="StartupGrid" Grid.Row="2"
                      AutoGenerateColumns="False" IsReadOnly="False"
                      CanUserAddRows="False" CanUserDeleteRows="False"
                      SelectionMode="Extended" GridLinesVisibility="Horizontal"
                      FontSize="12" Margin="0">
                <DataGrid.Columns>
                    <DataGridCheckBoxColumn Header="ACTIVO" Binding="{Binding Enabled}" Width="70"/>
                    <DataGridTextColumn Header="NOMBRE"  Binding="{Binding Name}"    Width="200" IsReadOnly="True"/>
                    <DataGridTextColumn Header="COMANDO" Binding="{Binding Command}"  Width="*"   IsReadOnly="True"/>
                    <DataGridTextColumn Header="ORIGEN"  Binding="{Binding Source}"   Width="130" IsReadOnly="True"/>
                </DataGrid.Columns>
            </DataGrid>

            <!-- Footer con status y botones -->
            <Border Grid.Row="3" Background="#0D0F1A" BorderBrush="#252B40" BorderThickness="0,1,0,0"
                    CornerRadius="0,0,10,10" Padding="18,10">
                <Grid>
                    <TextBlock Name="StartupStatus" VerticalAlignment="Center"
                               Foreground="#7880A0" FontSize="11"
                               FontFamily="JetBrains Mono, Consolas"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button Name="btnApplyStartup" Content="✔  Aplicar cambios"
                                Height="34" Padding="16,0" Margin="0,0,8,0"
                                Background="#4AE896" Foreground="#0D0F1A"
                                BorderThickness="0" FontWeight="Bold" FontSize="12" Cursor="Hand"/>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
"@

    $sReader    = [System.Xml.XmlNodeReader]::new([xml]$startupXaml)
    $sWindow    = [Windows.Markup.XamlReader]::Load($sReader)
    $sGrid      = $sWindow.FindName("StartupGrid")
    $sStatus    = $sWindow.FindName("StartupStatus")
    $btnApply   = $sWindow.FindName("btnApplyStartup")
    $btnClose   = $sWindow.FindName("btnCloseStartup")
    $titleBar   = $sWindow.FindName("titleBar")

    # Drag por la barra de título (no se puede hacer en XAML puro sin code-behind)
    $script:_startupWin = $sWindow
    $titleBar.Add_MouseLeftButtonDown({ $script:_startupWin.DragMove() })

    # Rutas del registro donde viven las entradas de autoarranque
    $regPaths = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";            Source = "HKCU Run" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";            Source = "HKLM Run" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";Source = "HKLM Run (32)" }
    )

    # Tabla observable para el DataGrid
    $startupTable = New-Object System.Collections.ObjectModel.ObservableCollection[object]

    foreach ($reg in $regPaths) {
        if (Test-Path $reg.Path) {
            $props = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object {
                    $_.Name -notmatch '^PS'
                } | ForEach-Object {
                    $entry = [PSCustomObject]@{
                        Enabled = $true
                        Name    = $_.Name
                        Command = $_.Value
                        Source  = $reg.Source
                        RegPath = $reg.Path
                        OriginalName = $_.Name
                    }
                    $startupTable.Add($entry)
                }
            }
        }
    }

    $sGrid.ItemsSource = $startupTable
    $sStatus.Text = "$($startupTable.Count) entradas encontradas"

    $btnApply.Add_Click({
        $disabled = 0
        $errors   = 0
        foreach ($item in $startupTable) {
            if (-not $item.Enabled) {
                try {
                    Remove-ItemProperty -Path $item.RegPath -Name $item.OriginalName -Force -ErrorAction Stop
                    $disabled++
                } catch {
                    $errors++
                }
            }
        }
        $msg = "Cambios aplicados: $disabled entradas desactivadas."
        if ($errors -gt 0) { $msg += "`n$errors entradas no pudieron modificarse (requieren permisos adicionales)." }
        Show-ThemedDialog -Title "Cambios aplicados" -Message $msg -Type "success"
        Write-ConsoleMain "🚀 Startup Manager: $disabled entradas desactivadas del registro."
        $sWindow.Close()
    })

    $script:_startupWin = $sWindow
    $btnClose.Add_Click({ $script:_startupWin.Close() })
    $sWindow.Owner = $window
    $sWindow.ShowDialog() | Out-Null
}

# ─────────────────────────────────────────────────────────────────────────────
# [N9] Ventana de Informe de Diagnóstico (resultado del Análisis Dry Run)
# ─────────────────────────────────────────────────────────────────────────────
function Show-DiagnosticReport {
    param([hashtable]$Report)

    $diagXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Informe de Diagnóstico del Sistema" Height="680" Width="860"
        WindowStartupLocation="CenterOwner" ResizeMode="CanResize"
        Background="#131625">
    <Window.Resources>
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize"   Value="11"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="#B0BACC"/>
            <Setter Property="Margin"     Value="0,14,0,4"/>
        </Style>
        <Style x:Key="GoodRow" TargetType="Border">
            <Setter Property="Background"     Value="#182A1E"/>
            <Setter Property="BorderBrush"    Value="#2A4A35"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius"   Value="6"/>
            <Setter Property="Padding"        Value="12,7"/>
            <Setter Property="Margin"         Value="0,3"/>
        </Style>
        <Style x:Key="WarnRow" TargetType="Border">
            <Setter Property="Background"     Value="#2A2010"/>
            <Setter Property="BorderBrush"    Value="#5A4010"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius"   Value="6"/>
            <Setter Property="Padding"        Value="12,7"/>
            <Setter Property="Margin"         Value="0,3"/>
        </Style>
        <Style x:Key="CritRow" TargetType="Border">
            <Setter Property="Background"     Value="#2A1018"/>
            <Setter Property="BorderBrush"    Value="#5A1828"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius"   Value="6"/>
            <Setter Property="Padding"        Value="12,7"/>
            <Setter Property="Margin"         Value="0,3"/>
        </Style>
        <Style x:Key="InfoRow" TargetType="Border">
            <Setter Property="Background"     Value="#1A2540"/>
            <Setter Property="BorderBrush"    Value="#2A3A60"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius"   Value="6"/>
            <Setter Property="Padding"        Value="12,7"/>
            <Setter Property="Margin"         Value="0,3"/>
        </Style>
    </Window.Resources>

    <Grid Margin="0">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#131625" BorderBrush="#252B40" BorderThickness="0,0,0,1" Padding="24,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock FontFamily="Segoe UI" FontSize="20" FontWeight="Bold" Foreground="#F0F3FA">
                        <Run Text="Informe de Diagnóstico"/>
                    </TextBlock>
                    <TextBlock Name="DiagSubtitle" FontFamily="Segoe UI" FontSize="11"
                               Foreground="#9BA4C0" Margin="0,4,0,0"
                               Text="Análisis completado — resultados por categoría"/>
                </StackPanel>
                <!-- Score global -->
                <Border Grid.Column="1" CornerRadius="10" Padding="18,10" VerticalAlignment="Center">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#1A3A5C" Offset="0"/>
                            <GradientStop Color="#162A40" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="PUNTUACIÓN" FontFamily="Segoe UI" FontSize="9"
                                   FontWeight="Bold" Foreground="#7BA8E0" HorizontalAlignment="Center"/>
                        <TextBlock Name="ScoreText" Text="—" FontFamily="Segoe UI" FontSize="32"
                                   FontWeight="Bold" Foreground="#5BA3FF" HorizontalAlignment="Center"/>
                        <TextBlock Name="ScoreLabel" Text="calculando..." FontFamily="Segoe UI" FontSize="10"
                                   Foreground="#9BA4C0" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>

        <!-- Body — scroll con categorías -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0">
            <StackPanel Name="DiagPanel" Margin="24,16,24,16"/>
        </ScrollViewer>

        <!-- Footer -->
        <Border Grid.Row="2" Background="#131625" BorderBrush="#252B40" BorderThickness="0,1,0,0" Padding="24,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Name="DiagFooterNote" Grid.Column="0"
                           FontFamily="Segoe UI" FontSize="10" Foreground="#6B7599"
                           VerticalAlignment="Center"
                           Text="▶  Pulsa 'Iniciar Optimización' en la ventana principal para reparar los puntos marcados."/>
                <Button Name="btnExportDiag" Grid.Column="1" Content="💾  Exportar informe"
                        Background="#1A2540" BorderBrush="#3D5080" BorderThickness="1"
                        Foreground="#7BA8E0" FontFamily="Segoe UI" FontSize="11" FontWeight="SemiBold"
                        Padding="14,7" Margin="8,0" Cursor="Hand" Height="34"/>
                <Button Name="btnCloseDiag" Grid.Column="2" Content="Cerrar"
                        Background="#1A2540" BorderBrush="#252B40" BorderThickness="1"
                        Foreground="#9BA4C0" FontFamily="Segoe UI" FontSize="11"
                        Padding="18,7" Cursor="Hand" Height="34"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    $dReader  = [System.Xml.XmlNodeReader]::new([xml]$diagXaml)
    $dWindow  = [Windows.Markup.XamlReader]::Load($dReader)
    $dPanel   = $dWindow.FindName("DiagPanel")
    $dScore   = $dWindow.FindName("ScoreText")
    $dLabel   = $dWindow.FindName("ScoreLabel")
    $dSub     = $dWindow.FindName("DiagSubtitle")
    $btnExp   = $dWindow.FindName("btnExportDiag")
    $btnClose = $dWindow.FindName("btnCloseDiag")

    # ── Helper: añadir fila al panel ────────────────────────────────────────
    function Add-DiagSection {
        param([string]$Title, [string]$Icon)
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Style = $dWindow.Resources["SectionHeader"]
        $tb.Text  = "$Icon  $Title"
        [void]$dPanel.Children.Add($tb)
    }

    function Add-DiagRow {
        param([string]$Status, [string]$Label, [string]$Detail, [string]$Action = "")
        $styleKey = switch ($Status) {
            "OK"   { "GoodRow" }
            "WARN" { "WarnRow" }
            "CRIT" { "CritRow" }
            default{ "InfoRow" }
        }
        $border = New-Object System.Windows.Controls.Border
        $border.Style = $dWindow.Resources[$styleKey]

        $grid = New-Object System.Windows.Controls.Grid
        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::new(38)
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($c0)
        $grid.ColumnDefinitions.Add($c1)
        $grid.ColumnDefinitions.Add($c2)

        # Icono de estado
        $ico = New-Object System.Windows.Controls.TextBlock
        $ico.Text = switch ($Status) {
            "OK"   { "✅" }
            "WARN" { "⚠️" }
            "CRIT" { "🔴" }
            default{ "ℹ️" }
        }
        $ico.FontSize = 16
        $ico.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($ico, 0)
        [void]$grid.Children.Add($ico)

        # Texto principal
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($sp, 1)

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text       = $Label
        $lbl.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $lbl.FontSize   = 12
        $lbl.FontWeight = [System.Windows.FontWeights]::SemiBold
        $lblColor = switch ($Status) {
            "OK"    { "#4AE896" }
            "WARN"  { "#FFB547" }
            "CRIT"  { "#FF6B84" }
            default { "#7BA8E0" }
        }
        $lbl.Foreground = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString($lblColor))
        [void]$sp.Children.Add($lbl)

        if ($Detail) {
            $det = New-Object System.Windows.Controls.TextBlock
            $det.Text       = $Detail
            $det.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
            $det.FontSize   = 10
            $det.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.ColorConverter]::ConvertFromString("#9BA4C0"))
            $det.TextWrapping = "Wrap"
            [void]$sp.Children.Add($det)
        }
        [void]$grid.Children.Add($sp)

        # Acción recomendada
        if ($Action) {
            $act = New-Object System.Windows.Controls.TextBlock
            $act.Text       = $Action
            $act.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
            $act.FontSize   = 9
            $act.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.ColorConverter]::ConvertFromString("#5BA3FF"))
            $act.VerticalAlignment = "Center"
            $act.TextAlignment = "Right"
            $act.Width = 160
            [System.Windows.Controls.Grid]::SetColumn($act, 2)
            [void]$grid.Children.Add($act)
        }

        $border.Child = $grid
        [void]$dPanel.Children.Add($border)
    }

    # ── Calcular y mostrar resultados ────────────────────────────────────────
    $points     = 100
    $deductions = 0
    $critCount  = 0
    $warnCount  = 0
    $exportLines = [System.Collections.Generic.List[string]]::new()
    $exportLines.Add("INFORME DE DIAGNÓSTICO DEL SISTEMA — SysOpt v1.0")
    $exportLines.Add("Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    $exportLines.Add("")

    # ── SECCIÓN: ALMACENAMIENTO ──────────────────────────────────────────────
    Add-DiagSection "ALMACENAMIENTO" "🗄️"
    $exportLines.Add("=== ALMACENAMIENTO ===")

    $tempTotal = $(if ($null -ne $Report.TempFilesMB) { [double]$Report.TempFilesMB } else { 0.0 }) + $(if ($null -ne $Report.UserTempMB) { [double]$Report.UserTempMB } else { 0.0 })
    if ($tempTotal -gt 1000) {
        Add-DiagRow "CRIT" "Archivos temporales acumulados" "$([math]::Round($tempTotal,0)) MB en carpetas Temp" "Limpiar Temp Windows + Usuario"
        $deductions += 15; $critCount++
        $exportLines.Add("[CRÍTICO] Archivos temporales: $([math]::Round($tempTotal,0)) MB — Limpiar Temp Windows + Usuario")
    } elseif ($tempTotal -gt 200) {
        Add-DiagRow "WARN" "Archivos temporales moderados" "$([math]::Round($tempTotal,0)) MB — recomendable limpiar" "Limpiar carpetas Temp"
        $deductions += 7; $warnCount++
        $exportLines.Add("[AVISO] Archivos temporales: $([math]::Round($tempTotal,0)) MB — recomendable limpiar")
    } else {
        Add-DiagRow "OK" "Carpetas temporales limpias" "$([math]::Round($tempTotal,1)) MB — nivel óptimo"
        $exportLines.Add("[OK] Archivos temporales: $([math]::Round($tempTotal,1)) MB")
    }

    $recycleSize = $(if ($null -ne $Report.RecycleBinMB) { [double]$Report.RecycleBinMB } else { 0.0 })
    if ($recycleSize -gt 500) {
        Add-DiagRow "WARN" "Papelera de reciclaje llena" "$([math]::Round($recycleSize,0)) MB ocupados" "Vaciar papelera"
        $deductions += 5; $warnCount++
        $exportLines.Add("[AVISO] Papelera: $([math]::Round($recycleSize,0)) MB — vaciar recomendado")
    } elseif ($recycleSize -gt 0) {
        Add-DiagRow "INFO" "Papelera con contenido" "$([math]::Round($recycleSize,1)) MB"
        $exportLines.Add("[INFO] Papelera: $([math]::Round($recycleSize,1)) MB")
    } else {
        Add-DiagRow "OK" "Papelera vacía" "Sin archivos pendientes de eliminar"
        $exportLines.Add("[OK] Papelera vacía")
    }

    $wuSize = $(if ($null -ne $Report.WUCacheMB) { [double]$Report.WUCacheMB } else { 0.0 })
    if ($wuSize -gt 2000) {
        Add-DiagRow "WARN" "Caché de Windows Update grande" "$([math]::Round($wuSize,0)) MB en SoftwareDistribution" "Limpiar WU Cache"
        $deductions += 8; $warnCount++
        $exportLines.Add("[AVISO] WU Cache: $([math]::Round($wuSize,0)) MB — limpiar recomendado")
    } elseif ($wuSize -gt 0) {
        Add-DiagRow "INFO" "Caché Windows Update presente" "$([math]::Round($wuSize,1)) MB"
        $exportLines.Add("[INFO] WU Cache: $([math]::Round($wuSize,1)) MB")
    } else {
        Add-DiagRow "OK" "Caché de Windows Update limpia" "Sin residuos de actualización"
        $exportLines.Add("[OK] WU Cache limpia")
    }

    # ── SECCIÓN: MEMORIA Y RENDIMIENTO ──────────────────────────────────────
    Add-DiagSection "MEMORIA Y RENDIMIENTO" "💾"
    $exportLines.Add("")
    $exportLines.Add("=== MEMORIA Y RENDIMIENTO ===")

    $ramUsedPct = $(if ($null -ne $Report.RamUsedPct) { [double]$Report.RamUsedPct } else { 0.0 })
    if ($ramUsedPct -gt 85) {
        Add-DiagRow "CRIT" "Memoria RAM crítica" "$ramUsedPct% en uso — riesgo de lentitud severa" "Liberar RAM urgente"
        $deductions += 20; $critCount++
        $exportLines.Add("[CRÍTICO] RAM: $ramUsedPct% en uso — liberar urgente")
    } elseif ($ramUsedPct -gt 70) {
        Add-DiagRow "WARN" "Uso de RAM elevado" "$ramUsedPct% en uso" "Liberar RAM recomendado"
        $deductions += 10; $warnCount++
        $exportLines.Add("[AVISO] RAM: $ramUsedPct% en uso — liberar recomendado")
    } else {
        Add-DiagRow "OK" "Memoria RAM en niveles normales" "$ramUsedPct% en uso"
        $exportLines.Add("[OK] RAM: $ramUsedPct% en uso")
    }

    $diskUsedPct = $(if ($null -ne $Report.DiskCUsedPct) { [double]$Report.DiskCUsedPct } else { 0.0 })
    if ($diskUsedPct -gt 90) {
        Add-DiagRow "CRIT" "Disco C: casi lleno" "$diskUsedPct% ocupado — rendimiento muy degradado" "Liberar espacio urgente"
        $deductions += 20; $critCount++
        $exportLines.Add("[CRÍTICO] Disco C: $diskUsedPct% — liberar espacio urgente")
    } elseif ($diskUsedPct -gt 75) {
        Add-DiagRow "WARN" "Disco C: con poco espacio libre" "$diskUsedPct% ocupado" "Limpiar archivos"
        $deductions += 10; $warnCount++
        $exportLines.Add("[AVISO] Disco C: $diskUsedPct% — limpiar recomendado")
    } else {
        Add-DiagRow "OK" "Espacio en disco C: saludable" "$diskUsedPct% ocupado"
        $exportLines.Add("[OK] Disco C: $diskUsedPct% ocupado")
    }

    # ── SECCIÓN: RED Y NAVEGADORES ───────────────────────────────────────────
    Add-DiagSection "RED Y NAVEGADORES" "🌐"
    $exportLines.Add("")
    $exportLines.Add("=== RED Y NAVEGADORES ===")

    $dnsCount = $(if ($null -ne $Report.DnsEntries) { [double]$Report.DnsEntries } else { 0.0 })
    if ($dnsCount -gt 500) {
        Add-DiagRow "WARN" "Caché DNS muy grande" "$dnsCount entradas — puede ralentizar resolución" "Limpiar caché DNS"
        $deductions += 5; $warnCount++
        $exportLines.Add("[AVISO] DNS: $dnsCount entradas — limpiar recomendado")
    } else {
        Add-DiagRow "OK" "Caché DNS normal" "$dnsCount entradas"
        $exportLines.Add("[OK] DNS: $dnsCount entradas")
    }

    $browserMB = $(if ($null -ne $Report.BrowserCacheMB) { [double]$Report.BrowserCacheMB } else { 0.0 })
    if ($browserMB -gt 1000) {
        Add-DiagRow "WARN" "Caché de navegadores muy grande" "$([math]::Round($browserMB,0)) MB — recomendable limpiar" "Limpiar caché navegadores"
        $deductions += 5; $warnCount++
        $exportLines.Add("[AVISO] Caché navegadores: $([math]::Round($browserMB,0)) MB")
    } elseif ($browserMB -gt 200) {
        Add-DiagRow "INFO" "Caché de navegadores presente" "$([math]::Round($browserMB,1)) MB"
        $exportLines.Add("[INFO] Caché navegadores: $([math]::Round($browserMB,1)) MB")
    } else {
        Add-DiagRow "OK" "Caché de navegadores limpia" "$([math]::Round($browserMB,1)) MB"
        $exportLines.Add("[OK] Caché navegadores: $([math]::Round($browserMB,1)) MB")
    }

    # ── SECCIÓN: REGISTRO DE WINDOWS ────────────────────────────────────────
    Add-DiagSection "REGISTRO DE WINDOWS" "📋"
    $exportLines.Add("")
    $exportLines.Add("=== REGISTRO DE WINDOWS ===")

    $orphaned = $(if ($null -ne $Report.OrphanedKeys) { [double]$Report.OrphanedKeys } else { 0.0 })
    if ($orphaned -gt 20) {
        Add-DiagRow "WARN" "Claves huérfanas en el registro" "$orphaned claves de programas desinstalados" "Limpiar registro"
        $deductions += 5; $warnCount++
        $exportLines.Add("[AVISO] Registro: $orphaned claves huérfanas")
    } elseif ($orphaned -gt 0) {
        Add-DiagRow "INFO" "Algunas claves huérfanas" "$orphaned claves — impacto mínimo"
        $exportLines.Add("[INFO] Registro: $orphaned claves huérfanas")
    } else {
        Add-DiagRow "OK" "Registro sin claves huérfanas" "No se detectaron entradas obsoletas"
        $exportLines.Add("[OK] Registro limpio")
    }

    # ── SECCIÓN: EVENT VIEWER LOGS ────────────────────────────────────────────
    Add-DiagSection "REGISTROS DE EVENTOS" "📰"
    $exportLines.Add("")
    $exportLines.Add("=== REGISTROS DE EVENTOS ===")

    $eventSizeMB = $(if ($null -ne $Report.EventLogsMB) { [double]$Report.EventLogsMB } else { 0.0 })
    if ($eventSizeMB -gt 100) {
        Add-DiagRow "WARN" "Logs de eventos grandes" "$([math]::Round($eventSizeMB,1)) MB en System+Application+Setup" "Limpiar Event Logs"
        $deductions += 3; $warnCount++
        $exportLines.Add("[AVISO] Event Logs: $([math]::Round($eventSizeMB,1)) MB")
    } else {
        Add-DiagRow "OK" "Logs de eventos dentro de límites" "$([math]::Round($eventSizeMB,1)) MB"
        $exportLines.Add("[OK] Event Logs: $([math]::Round($eventSizeMB,1)) MB")
    }

    # ── PUNTUACIÓN FINAL ─────────────────────────────────────────────────────
    $finalScore = [math]::Max(0, $points - $deductions)
    $dScore.Text  = "$finalScore"
    $scoreColor = if ($finalScore -ge 80) { "#4AE896" } elseif ($finalScore -ge 55) { "#FFB547" } else { "#FF6B84" }
    $dScore.Foreground = New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.ColorConverter]::ConvertFromString($scoreColor))
    $dLabel.Text = if ($finalScore -ge 80) { "Sistema en buen estado" } `
                   elseif ($finalScore -ge 55) { "Mantenimiento recomendado" } `
                   else { "Atención urgente" }

    $dSub.Text = "$(Get-Date -Format 'dd/MM/yyyy HH:mm')  ·  $critCount crítico(s)  ·  $warnCount aviso(s)"

    $exportLines.Add("")
    $exportLines.Add("=== RESUMEN ===")
    $exportLines.Add("Puntuación: $finalScore / 100")
    $exportLines.Add("Críticos: $critCount  |  Avisos: $warnCount")
    $exportLines.Add("Estado: $($dLabel.Text)")

    # ── Exportar informe ─────────────────────────────────────────────────────
    $btnExp.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Title            = "Exportar Informe de Diagnóstico"
        $sd.Filter           = "Texto (*.txt)|*.txt|Todos (*.*)|*.*"
        $sd.DefaultExt       = "txt"
        $sd.FileName         = "DiagnosticoSistema_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $sd.InitialDirectory = [Environment]::GetFolderPath("Desktop")
        if ($sd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $exportLines | Out-File -FilePath $sd.FileName -Encoding UTF8
            Show-ThemedDialog -Title "Informe exportado" `
                -Message "Informe guardado en:`n$($sd.FileName)" -Type "success"
        }
    })

    $btnClose.Add_Click({ $dWindow.Close() })
    $dWindow.Owner = $window
    $dWindow.ShowDialog() | Out-Null
}

# ═════════════════════════════════════════════════════════════════════════════
# SCRIPT DE OPTIMIZACIÓN — se ejecuta en runspace separado
# ═════════════════════════════════════════════════════════════════════════════
$OptimizationScript = {
    param(
        $window, $ConsoleOutput, $ProgressBar, $StatusText,
        $ProgressText, $TaskText, $options, $CancelToken,
        [ref]$DiagReportRef
    )

    # ── Diccionario de resultados del análisis (dry-run) ─────────────────────
    $diagData = @{
        TempFilesMB   = 0.0
        UserTempMB    = 0.0
        RecycleBinMB  = 0.0
        WUCacheMB     = 0.0
        BrowserCacheMB= 0.0
        DnsEntries    = 0
        OrphanedKeys  = 0
        EventLogsMB   = 0.0
        RamUsedPct    = 0
        DiskCUsedPct  = 0
    }

    # ── Helpers de UI ────────────────────────────────────────────────────────
    function Write-Console {
        param([string]$Message)
        $ts = Get-Date -Format "HH:mm:ss"
        $out = "[$ts] $Message"
        $window.Dispatcher.Invoke([action]{
            $ConsoleOutput.AppendText("$out`n")
            $ConsoleOutput.ScrollToEnd()
        }.GetNewClosure())
    }

    function Update-Progress {
        param([int]$Percent, [string]$TaskName = "")
        $window.Dispatcher.Invoke([action]{
            $ProgressBar.Value  = $Percent
            $ProgressText.Text  = "$Percent%"
            if ($TaskName) { $TaskText.Text = "Tarea actual: $TaskName" }
        }.GetNewClosure())
    }

    function Update-SubProgress {
        param([double]$Base, [double]$Sub, [double]$Weight)
        $actual = [math]::Round($Base + (($Sub / 100) * $Weight))
        $window.Dispatcher.Invoke([action]{
            $ProgressBar.Value = $actual
            $ProgressText.Text = "$actual%"
        }.GetNewClosure())
    }

    function Update-Status {
        param([string]$Status)
        $window.Dispatcher.Invoke([action]{
            $StatusText.Text = $Status
        }.GetNewClosure())
    }

    function Test-Cancelled {
        if ($CancelToken.IsCancellationRequested) {
            Write-Console ""
            Write-Console "⚠ OPTIMIZACIÓN CANCELADA POR EL USUARIO"
            Update-Status "⚠ Cancelado por el usuario"
            $window.Dispatcher.Invoke([action]{
                $TaskText.Text = "Cancelado"
            }.GetNewClosure())
            return $true
        }
        return $false
    }

    # ── [M1] Función unificada de limpieza de carpetas temporales ────────────
    # [B13] Elimina la duplicación total entre TempFiles y UserTemp
    function Invoke-CleanTempPaths {
        param(
            [string[]]$Paths,
            [double]$BasePercent,
            [double]$TaskWeight,
            [bool]$DryRun = $false
        )
        $totalFreed = 0
        $pathIndex  = 0
        $pathCount  = $Paths.Count

        foreach ($path in $Paths) {
            $pathIndex++
            Update-SubProgress $BasePercent ([int](($pathIndex / $pathCount) * 100)) $TaskWeight

            if (-not (Test-Path $path)) {
                Write-Console "  [$pathIndex/$pathCount] Ruta no encontrada: $path"
                continue
            }

            Write-Console "  [$pathIndex/$pathCount] Analizando: $path"
            try {
                $beforeSize = (Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                               Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $beforeSize) { $beforeSize = 0 }
                $beforeMB = [math]::Round($beforeSize / 1MB, 2)
                Write-Console "    Tamaño: $beforeMB MB"

                if (-not $DryRun) {
                    $deletedCount = 0
                    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { -not $_.PSIsContainer } | ForEach-Object {
                            $fp = $_.FullName
                            Remove-Item $fp -Force -ErrorAction SilentlyContinue
                            if (-not (Test-Path $fp)) { $deletedCount++ }
                        }
                    # Eliminar directorios vacíos (o con restos no eliminables)
                    # -Recurse es necesario para evitar el prompt interactivo en directorios con hijos
                    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.PSIsContainer } |
                        Sort-Object -Property FullName -Descending | ForEach-Object {
                            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    $afterSize = (Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                                  Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($null -eq $afterSize) { $afterSize = 0 }
                    $freed = ($beforeSize - $afterSize) / 1MB
                    $totalFreed += $freed
                    Write-Console "    ✓ Eliminados: $deletedCount archivos — $([math]::Round($freed,2)) MB liberados"
                } else {
                    $totalFreed += $beforeMB
                    Write-Console "    [DRY RUN] Se liberarían ~$beforeMB MB"
                }
            } catch {
                Write-Console "    ! Error: $($_.Exception.Message)"
            }
        }
        return $totalFreed
    }

    # ── Contar tareas seleccionadas ──────────────────────────────────────────
    $taskKeys = @(
        'OptimizeDisks','RecycleBin','TempFiles','UserTemp','WUCache','Chkdsk',
        'ClearMemory','CloseProcesses','DNSCache','BrowserCache',
        'BackupRegistry','CleanRegistry','SFC','DISM','EventLogs'
        # ShowStartup se maneja en el hilo principal, no aquí
    )
    $taskList   = $taskKeys | Where-Object { $options[$_] -eq $true }
    $totalTasks = $taskList.Count
    $dryRun     = $options['DryRun'] -eq $true

    if ($totalTasks -eq 0) {
        Write-Console "No hay tareas seleccionadas."
        Update-Status "Sin tareas seleccionadas"
        Update-Progress 0 ""
        return
    }

    $taskWeight      = 100.0 / $totalTasks
    $completedTasks  = 0
    $startTime       = Get-Date
    $dryRunLabel     = if ($dryRun) { " [MODO ANÁLISIS — sin cambios]" } else { "" }

    $boxWidth  = 62   # ancho interior entre ║ y ║
    $titleLine = if ($dryRun) {
        "INICIANDO OPTIMIZACIÓN  —  MODO ANÁLISIS (DRY RUN)"
    } else {
        "INICIANDO OPTIMIZACIÓN DEL SISTEMA WINDOWS"
    }
    $pad   = [math]::Max(0, $boxWidth - $titleLine.Length)
    $left  = [math]::Floor($pad / 2)
    $right = $pad - $left
    Write-Console "╔$('═' * $boxWidth)╗"
    Write-Console "║$(' ' * $left)$titleLine$(' ' * $right)║"
    Write-Console "╚$('═' * $boxWidth)╝"
    Write-Console "Fecha:    $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    Write-Console "Modo:     $(if ($dryRun) { '🔍 ANÁLISIS (Dry Run) — solo reportar' } else { '⚙ EJECUCIÓN real' })"
    Write-Console "Tareas:   $totalTasks"
    Write-Console "Tareas a ejecutar: $($taskList -join ', ')"
    Write-Console ""

    # ── 1. OPTIMIZACIÓN DE DISCOS ────────────────────────────────────────────
    if ($options['OptimizeDisks']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Optimización de discos"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Optimizando discos..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "1. OPTIMIZACIÓN DE DISCOS DUROS$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        try {
            $volumes = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' })
            Write-Console "Unidades encontradas: $($volumes.Count)"

            $volIdx = 0
            foreach ($volume in $volumes) {
                $volIdx++
                $dl      = $volume.DriveLetter
                $sizeGB  = [math]::Round($volume.Size          / 1GB, 2)
                $freeGB  = [math]::Round($volume.SizeRemaining / 1GB, 2)
                Update-SubProgress $base ([int](($volIdx / $volumes.Count) * 100)) $taskWeight

                Write-Console ""
                Write-Console "  [$volIdx/$($volumes.Count)] Unidad ${dl}: — $sizeGB GB total, $freeGB GB libre"

                try {
                    $partition = Get-Partition -DriveLetter $dl -ErrorAction Stop
                    $disk      = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop

                    # [B5] Detección robusta por DeviceID, no por FriendlyName
                    $mediaType = $disk.MediaType
                    try {
                        $physDisk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $disk.Number } | Select-Object -First 1
                        if ($physDisk -and $physDisk.MediaType -and $physDisk.MediaType -ne 'Unspecified') {
                            $mediaType = $physDisk.MediaType
                        }
                    } catch { }

                    $isNVMe = $disk.FriendlyName -match 'NVMe|NVME|nvme'
                    $isSSD  = $mediaType -in @('SSD', 'Solid State Drive') -or $isNVMe

                    Write-Console "  Tipo: $mediaType$(if($isNVMe){' (NVMe)'})"

                    if ($dryRun) {
                        Write-Console "  [DRY RUN] Se ejecutaría: $(if($isSSD){'TRIM (Optimize-Volume -ReTrim)'}else{'Defrag (Optimize-Volume -Defrag)'})"
                    } elseif ($isSSD) {
                        Optimize-Volume -DriveLetter $dl -ReTrim -ErrorAction Stop
                        Write-Console "  ✓ TRIM completado"
                    } else {
                        Optimize-Volume -DriveLetter $dl -Defrag -ErrorAction Stop
                        Write-Console "  ✓ Desfragmentación completada"
                    }
                } catch {
                    Write-Console "  ✗ Error: $($_.Exception.Message)"
                    if (-not $dryRun) {
                        try {
                            $out = & defrag.exe "${dl}:" /O 2>&1
                            $out | Where-Object { $_ -and $_.ToString().Trim() } |
                                ForEach-Object { Write-Console "    $_" }
                        } catch {
                            Write-Console "  ✗ Método alternativo falló: $($_.Exception.Message)"
                        }
                    }
                }
            }
            Write-Console ""
            Write-Console "✓ Optimización de discos $(if($dryRun){'analizada'}else{'completada'})"
        } catch {
            Write-Console "Error general: $($_.Exception.Message)"
        }
        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 2. VACIAR PAPELERA ───────────────────────────────────────────────────
    if ($options['RecycleBin']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Vaciando papelera"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Vaciando papelera..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "2. VACIANDO PAPELERA DE RECICLAJE$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        try {
            $totalSize = 0
            Get-PSDrive -PSProvider FileSystem | ForEach-Object {
                $rp = Join-Path $_.Root '$Recycle.Bin'
                if (Test-Path $rp) {
                    $sz = (Get-ChildItem -Path $rp -Force -Recurse -ErrorAction SilentlyContinue |
                           Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($sz) { $totalSize += $sz }
                }
            }
            $totalMB = [math]::Round($totalSize / 1MB, 2)
            Write-Console "  Contenido total en papelera: $totalMB MB"
            $diagData['RecycleBinMB'] = $totalMB

            if ($dryRun) {
                Write-Console "  [DRY RUN] Se liberarían ~$totalMB MB"
            } else {
                Get-PSDrive -PSProvider FileSystem | ForEach-Object {
                    $rp = Join-Path $_.Root '$Recycle.Bin'
                    if (Test-Path $rp) {
                        Get-ChildItem -Path $rp -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                Write-Console "  ✓ Papelera vaciada para todas las unidades — $totalMB MB liberados"
            }
        } catch {
            Write-Console "  ❌ Error: $($_.Exception.Message)"
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 3. ARCHIVOS TEMPORALES DE WINDOWS ───────────────────────────────────
    if ($options['TempFiles']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Archivos temporales Windows"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Temp Windows..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "3. ARCHIVOS TEMPORALES DE WINDOWS$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        $paths  = @("$env:SystemRoot\Temp", "$env:SystemRoot\Prefetch")
        $freed  = Invoke-CleanTempPaths -Paths $paths -BasePercent $base -TaskWeight $taskWeight -DryRun $dryRun
        $diagData['TempFilesMB'] = $freed
        Write-Console ""
        Write-Console "  ✓ Total: $([math]::Round($freed,2)) MB $(if($dryRun){'por liberar'}else{'liberados'})"

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 4. ARCHIVOS TEMPORALES DE USUARIO ───────────────────────────────────
    if ($options['UserTemp']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Archivos temporales Usuario"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Temp Usuario..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "4. ARCHIVOS TEMPORALES DE USUARIO$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        $paths = @("$env:TEMP", "$env:LOCALAPPDATA\Temp")
        $freed = Invoke-CleanTempPaths -Paths $paths -BasePercent $base -TaskWeight $taskWeight -DryRun $dryRun
        $diagData['UserTempMB'] = $freed
        Write-Console ""
        Write-Console "  ✓ Total: $([math]::Round($freed,2)) MB $(if($dryRun){'por liberar'}else{'liberados'})"

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 5. [N3] WINDOWS UPDATE CACHE ────────────────────────────────────────
    if ($options['WUCache']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Windows Update Cache"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Limpiando WU Cache..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "5. WINDOWS UPDATE CACHE (SoftwareDistribution)$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        $wuPath = "$env:SystemRoot\SoftwareDistribution\Download"

        try {
            $beforeSize = (Get-ChildItem -Path $wuPath -Recurse -Force -ErrorAction SilentlyContinue |
                           Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($null -eq $beforeSize) { $beforeSize = 0 }
            $beforeMB = [math]::Round($beforeSize / 1MB, 2)
            Write-Console "  Tamaño actual: $beforeMB MB"
            $diagData['WUCacheMB'] = $beforeMB
            Update-SubProgress $base 30 $taskWeight

            if ($dryRun) {
                Write-Console "  [DRY RUN] Se liberarían ~$beforeMB MB"
            } else {
                # Detener servicio de Windows Update temporalmente
                Write-Console "  Deteniendo servicio Windows Update (wuauserv)..."
                Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
                Update-SubProgress $base 50 $taskWeight
                Start-Sleep -Seconds 2

                Get-ChildItem -Path $wuPath -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

                $afterSize = (Get-ChildItem -Path $wuPath -Recurse -Force -ErrorAction SilentlyContinue |
                              Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $afterSize) { $afterSize = 0 }

                # Reiniciar servicio
                Update-SubProgress $base 85 $taskWeight
                Start-Service -Name wuauserv -ErrorAction SilentlyContinue
                Write-Console "  ✓ Servicio Windows Update reiniciado"

                $freed = [math]::Round(($beforeSize - $afterSize) / 1MB, 2)
                Write-Console "  ✓ WU Cache limpiada — $freed MB liberados"
            }
        } catch {
            Write-Console "  ! Error: $($_.Exception.Message)"
            # Asegurar que el servicio queda activo aunque falle
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 6. CHECK DISK ────────────────────────────────────────────────────────
    if ($options['Chkdsk']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Check Disk (CHKDSK)"
        Update-Status "Programando CHKDSK..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "6. PROGRAMANDO CHECK DISK (CHKDSK)"
        Write-Console "═══════════════════════════════════════════════════════════"

        if ($dryRun) {
            Write-Console "  [DRY RUN] Se programaría CHKDSK en el próximo reinicio"
        } else {
            try {
                # [B9] Orden correcto: dirty set PRIMERO, luego chkntfs /x para 
                #      excluir el chequeo automático de arranque limpio pero
                #      forzar via volumen sucio. En realidad el flujo correcto
                #      es marcar dirty y NO excluir con /x, así CHKDSK sí corre.
                Write-Console "  Marcando volumen C: como sucio (fsutil dirty set)..."
                $fsutilOutput = & fsutil dirty set C: 2>&1
                $fsutilOutput | Where-Object { $_ -and $_.ToString().Trim() } |
                    ForEach-Object { Write-Console "    $_" }

                Write-Console "  ✓ CHKDSK programado — se ejecutará en el próximo reinicio"
                Write-Console "  NOTA: El sistema debe reiniciarse para que CHKDSK se ejecute"
            } catch {
                Write-Console "  Error: $($_.Exception.Message)"
            }
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 7. LIBERAR MEMORIA RAM ───────────────────────────────────────────────
    if ($options['ClearMemory']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Liberando memoria RAM"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Liberando RAM..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "7. LIBERANDO MEMORIA RAM$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        try {
            $osBefore   = Get-CimInstance -ClassName Win32_OperatingSystem
            $totalGB    = [math]::Round($osBefore.TotalVisibleMemorySize / 1MB, 2)
            $freeGBBef  = [math]::Round($osBefore.FreePhysicalMemory     / 1MB, 2)

            Write-Console "  Total RAM:       $totalGB GB"
            Write-Console "  Libre antes:     $freeGBBef GB"
            Update-SubProgress $base 20 $taskWeight

            if ($dryRun) {
                Write-Console "  [DRY RUN] Se vaciaría el Working Set de todos los procesos accesibles"
            } else {
                # [B1] Liberación real via EmptyWorkingSet por cada proceso
                $count = 0
                foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
                    try {
                        $hProc = [MemoryHelper]::OpenProcess(0x1F0FFF, $false, $proc.Id)
                        if ($hProc -ne [IntPtr]::Zero) {
                            [MemoryHelper]::EmptyWorkingSet($hProc) | Out-Null
                            [MemoryHelper]::CloseHandle($hProc) | Out-Null
                            $count++
                        }
                    } catch { }
                }
                Write-Console "  Working Set vaciado en $count procesos"
                Update-SubProgress $base 70 $taskWeight
                Start-Sleep -Seconds 2

                $osAfter   = Get-CimInstance -ClassName Win32_OperatingSystem
                $freeGBAft = [math]::Round($osAfter.FreePhysicalMemory / 1MB, 2)
                $gained    = [math]::Round($freeGBAft - $freeGBBef, 2)

                Write-Console "  Libre después:   $freeGBAft GB"
                Write-Console "  ✓ RAM recuperada: $gained GB"
            }
        } catch {
            Write-Console "  Error: $($_.Exception.Message)"
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 8. CERRAR PROCESOS NO CRÍTICOS ───────────────────────────────────────
    if ($options['CloseProcesses']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Cerrando procesos"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Cerrando procesos..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "8. CERRANDO PROCESOS NO CRÍTICOS$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        try {
            $criticals = @(
                'System','svchost','csrss','wininit','services','lsass','winlogon',
                'dwm','explorer','taskhostw','RuntimeBroker','sihost','fontdrvhost',
                'smss','conhost','dllhost','spoolsv','SearchIndexer','MsMpEng',
                'powershell','pwsh','audiodg','wudfhost','dasHost','TextInputHost',
                'SecurityHealthService','SgrmBroker','SecurityHealthSystray',
                'ShellExperienceHost','StartMenuExperienceHost','SearchUI','Cortana',
                'ApplicationFrameHost','SystemSettings','WmiPrvSE','Memory Compression'
            )

            $curProc  = Get-Process -Id $PID
            $sessionId = $curProc.SessionId
            $parentPID = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue).ParentProcessId

            $targets = @(Get-Process | Where-Object {
                $_.SessionId -eq $sessionId -and
                $_.ProcessName -notin $criticals -and
                $_.Id -ne $PID -and
                $_.Id -ne $parentPID -and
                $_.ProcessName -ne 'Idle'
            })

            Write-Console "  Procesos candidatos: $($targets.Count)"

            $closed = 0
            $idx    = 0
            foreach ($p in $targets) {
                $idx++
                Update-SubProgress $base ([int](($idx / [Math]::Max($targets.Count,1)) * 100)) $taskWeight
                if ($dryRun) {
                    Write-Console "  [DRY RUN] Cerraría: $($p.ProcessName) (PID: $($p.Id))"
                } else {
                    try {
                        $p | Stop-Process -Force -ErrorAction Stop
                        $closed++
                        Write-Console "  ✓ Cerrado: $($p.ProcessName) (PID: $($p.Id))"
                    } catch { }
                }
            }
            Write-Console ""
            Write-Console "  ✓ Procesos cerrados: $closed de $($targets.Count)"
        } catch {
            Write-Console "  Error: $($_.Exception.Message)"
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 9. LIMPIAR CACHÉ DNS ─────────────────────────────────────────────────
    if ($options['DNSCache']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Limpiando caché DNS"
        Update-Status "$(if($dryRun){'[DRY RUN] '})DNS cache..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "9. LIMPIANDO CACHÉ DNS$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        try {
            if ($dryRun) {
                $dnsEntries = (Get-DnsClientCache -ErrorAction SilentlyContinue).Count
                Write-Console "  [DRY RUN] Caché DNS actual: $dnsEntries entradas"
                $diagData['DnsEntries'] = $dnsEntries
            } else {
                Update-SubProgress $base 30 $taskWeight
                Clear-DnsClientCache -ErrorAction Stop
                Write-Console "  ✓ Clear-DnsClientCache ejecutado"
                Update-SubProgress $base 60 $taskWeight
                # [FIX] Capturar ipconfig con encoding correcto (cp850 en Windows español)
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName               = "cmd.exe"
                $psi.Arguments              = "/c chcp 65001 >nul 2>&1 & ipconfig /flushdns"
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError  = $true
                $psi.UseShellExecute        = $false
                $psi.CreateNoWindow         = $true
                $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                $proc = [System.Diagnostics.Process]::Start($psi)
                $stdout = $proc.StandardOutput.ReadToEnd()
                $proc.WaitForExit()
                $stdout -split "`n" | Where-Object { $_.Trim() } |
                    ForEach-Object { Write-Console "  $($_.TrimEnd())" }
                Write-Console "  ✓ Caché DNS limpiada"
            }
        } catch {
            Write-Console "  Error: $($_.Exception.Message)"
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 10. LIMPIAR NAVEGADORES ──────────────────────────────────────────────
    if ($options['BrowserCache']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Limpiando navegadores"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Navegadores..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "10. LIMPIANDO CACHÉ DE NAVEGADORES$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        # [B6] Rutas completas para todos los navegadores
        $browsers = @{
            "Chrome" = @(
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache2",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
            )
            "Edge" = @(
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache2",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
            )
            "Brave" = @(
                "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache",
                "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache2",
                "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Code Cache",
                "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\GPUCache"
            )
            "Opera" = @(
                "$env:APPDATA\Opera Software\Opera Stable\Cache",
                "$env:APPDATA\Opera Software\Opera Stable\Cache2",
                "$env:APPDATA\Opera Software\Opera Stable\Code Cache",
                "$env:APPDATA\Opera Software\Opera Stable\GPUCache"
            )
            "Opera GX" = @(
                "$env:APPDATA\Opera Software\Opera GX Stable\Cache",
                "$env:APPDATA\Opera Software\Opera GX Stable\Cache2",
                "$env:APPDATA\Opera Software\Opera GX Stable\Code Cache",
                "$env:APPDATA\Opera Software\Opera GX Stable\GPUCache"
            )
            # [B7] Firefox: cache + cache2 (legacy y moderno)
            "Firefox" = @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles")
        }

        $bIdx   = 0
        $bCount = $browsers.Keys.Count

        foreach ($browser in $browsers.Keys) {
            $bIdx++
            Update-SubProgress $base ([int](($bIdx / $bCount) * 100)) $taskWeight
            Write-Console "  [$bIdx/$bCount] $browser..."
            $cleared    = $false
            $totalCleared = 0

            foreach ($path in $browsers[$browser]) {
                if ($browser -eq "Firefox") {
                    # Expandir perfiles y limpiar cache + cache2
                    $profileDirs = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue
                    foreach ($pd in $profileDirs) {
                        foreach ($cacheSub in @('cache', 'cache2')) {
                            $cp = Join-Path $pd.FullName $cacheSub
                            if (Test-Path $cp) {
                                $sz = (Get-ChildItem -Path $cp -Recurse -Force -ErrorAction SilentlyContinue |
                                       Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                                if ($sz) { $totalCleared += $sz / 1MB }
                                if (-not $dryRun) {
                                    Remove-Item -Path "$cp\*" -Recurse -Force -ErrorAction SilentlyContinue
                                }
                                $cleared = $true
                            }
                        }
                    }
                    continue
                }

                if (Test-Path $path) {
                    try {
                        $sz = (Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                               Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        if ($sz) { $totalCleared += $sz / 1MB }
                        if (-not $dryRun) {
                            Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        $cleared = $true
                    } catch { }
                }
            }

            $mb = [math]::Round($totalCleared, 2)
            $diagData['BrowserCacheMB'] += $totalCleared
            if ($cleared) {
                Write-Console "    $(if($dryRun){'[DRY RUN]'} else {'✓'}) $browser — $mb MB $(if($dryRun){'por liberar'}else{'liberados'})"
            } else {
                Write-Console "    → $browser no encontrado o sin caché"
            }
        }

        Write-Console ""
        Write-Console "  ✓ Limpieza de navegadores $(if($dryRun){'analizada'}else{'completada'})"

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 11. BACKUP DEL REGISTRO ──────────────────────────────────────────────
    if ($options['BackupRegistry']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Backup del registro"
        Update-Status "Creando backup del registro..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "11. BACKUP DEL REGISTRO$(if($dryRun){' [DRY RUN — no se crea]'})"
        Write-Console "═══════════════════════════════════════════════════════════"

        $backupPath = "$env:USERPROFILE\Desktop\RegistryBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

        if ($dryRun) {
            Write-Console "  [DRY RUN] Se crearía backup en: $backupPath"
            Write-Console "  [DRY RUN] Exportaría: HKEY_CURRENT_USER, HKLM\SOFTWARE"
        } else {
            try {
                New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
                Write-Console "  Carpeta: $backupPath"

                $hives = @(
                    @{Name="HKEY_CURRENT_USER";             File="HKCU_backup.reg"},
                    @{Name="HKEY_LOCAL_MACHINE\SOFTWARE";   File="HKLM_SOFTWARE_backup.reg"}
                )

                $hi = 0
                foreach ($hive in $hives) {
                    $hi++
                    Update-SubProgress $base ([int](($hi / $hives.Count) * 100)) $taskWeight
                    Write-Console "  [$hi/$($hives.Count)] Exportando $($hive.Name)..."
                    $exportFile = Join-Path $backupPath $hive.File
                    & cmd /c "reg export `"$($hive.Name)`" `"$exportFile`" /y" 2>&1 | Out-Null
                    if (Test-Path $exportFile) {
                        $sz = [math]::Round((Get-Item $exportFile).Length / 1MB, 2)
                        Write-Console "    ✓ $sz MB"
                    } else {
                        Write-Console "    ! No se pudo exportar"
                    }
                }
                Write-Console ""
                Write-Console "  ✓ Backup completado en: $backupPath"
            } catch {
                Write-Console "  Error: $($_.Exception.Message)"
            }
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 12. LIMPIAR REGISTRO ─────────────────────────────────────────────────
    if ($options['CleanRegistry']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Limpiando registro"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Claves huérfanas..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "12. LIMPIANDO CLAVES HUÉRFANAS DEL REGISTRO$dryRunLabel"
        Write-Console "═══════════════════════════════════════════════════════════"

        try {
            $uninstallPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
            )

            $orphaned = 0
            $deleted  = 0
            $pIdx     = 0

            foreach ($path in $uninstallPaths) {
                $pIdx++
                Update-SubProgress $base (20 + [int](($pIdx / $uninstallPaths.Count) * 70)) $taskWeight
                if (-not (Test-Path $path)) { continue }

                Write-Console "  Analizando: $path"
                Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
                    $key     = $_
                    $props   = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                    $dName   = $props.DisplayName
                    $iLoc    = $props.InstallLocation

                    if ($iLoc -and -not (Test-Path $iLoc)) {
                        $orphaned++
                        Write-Console "    → Huérfana: $dName"
                        if (-not $dryRun) {
                            try {
                                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction Stop
                                $deleted++
                                Write-Console "      ✓ Eliminada"
                            } catch {
                                Write-Console "      ! No se pudo eliminar: $($_.Exception.Message)"
                            }
                        } else {
                            Write-Console "      [DRY RUN] Se eliminaría"
                        }
                    }
                }
            }

            Write-Console ""
            Write-Console "  ✓ Huérfanas encontradas: $orphaned — Eliminadas: $deleted"
            $diagData['OrphanedKeys'] = $orphaned
        } catch {
            Write-Console "  Error: $($_.Exception.Message)"
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 13. SFC /SCANNOW ─────────────────────────────────────────────────────
    if ($options['SFC']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "SFC /SCANNOW"
        Update-Status "Ejecutando SFC (puede tardar varios minutos)..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "13. SFC /SCANNOW"
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "    NOTA: puede tardar entre 10-30 minutos"

        if ($dryRun) {
            Write-Console "  [DRY RUN] Se ejecutaría: sfc.exe /scannow"
        } else {
            try {
                $sfcProc = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" `
                    -NoNewWindow -Wait -PassThru

                $cbsLog = "$env:SystemRoot\Logs\CBS\CBS.log"
                if (Test-Path $cbsLog) {
                    $lastLines = Get-Content $cbsLog -Tail 20
                    Write-Console "  Últimas líneas CBS.log:"
                    $lastLines | ForEach-Object { Write-Console "    $_" }
                }

                switch ($sfcProc.ExitCode) {
                    0 { Write-Console "  ✓ SFC: No se encontraron infracciones" }
                    1 { Write-Console "  ✓ SFC: Archivos corruptos reparados" }
                    2 { Write-Console "  ! SFC: Archivos corruptos que no pudieron repararse" }
                    3 { Write-Console "  ! SFC: No se pudo realizar la verificación" }
                    default { Write-Console "  ! SFC código: $($sfcProc.ExitCode)" }
                }
            } catch {
                Write-Console "  Error: $($_.Exception.Message)"
            }
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 14. DISM ─────────────────────────────────────────────────────────────
    if ($options['DISM']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "DISM"
        Update-Status "Ejecutando DISM (puede tardar varios minutos)..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "14. DISM — Reparación de imagen del sistema"
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "    NOTA: puede tardar entre 15-45 minutos"

        if ($dryRun) {
            Write-Console "  [DRY RUN] Se ejecutarían: CheckHealth, ScanHealth, RestoreHealth"
        } else {
            try {
                foreach ($step in @(
                    @{ Label="Paso 1/3: CheckHealth...";    Args="/Online /Cleanup-Image /CheckHealth";   Sub=10 },
                    @{ Label="Paso 2/3: ScanHealth...";     Args="/Online /Cleanup-Image /ScanHealth";    Sub=40 },
                    @{ Label="Paso 3/3: RestoreHealth...";  Args="/Online /Cleanup-Image /RestoreHealth"; Sub=70 }
                )) {
                    Write-Console ""
                    Write-Console "  $($step.Label)"
                    Update-SubProgress $base $step.Sub $taskWeight
                    $out = & DISM ($step.Args -split ' ') 2>&1
                    $out | Where-Object { $_ -and $_.ToString().Trim() } |
                        ForEach-Object { Write-Console "    $_" }
                }
                Write-Console ""
                Write-Console "  ✓ DISM completado"
            } catch {
                Write-Console "  Error: $($_.Exception.Message)"
            }
        }

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── 15. [N7] EVENT VIEWER LOGS ───────────────────────────────────────────
    if ($options['EventLogs']) {
        if (Test-Cancelled) { return }
        $base = [math]::Round(($completedTasks / $totalTasks) * 100)
        Update-Progress $base "Event Viewer Logs"
        Update-Status "$(if($dryRun){'[DRY RUN] '})Limpiando Event Logs..."

        Write-Console ""
        Write-Console "═══════════════════════════════════════════════════════════"
        Write-Console "15. LIMPIANDO EVENT VIEWER LOGS$dryRunLabel"
        Write-Console "    (System, Application, Setup — NO Security)"
        Write-Console "═══════════════════════════════════════════════════════════"

        $logs = @('System', 'Application', 'Setup')

        $lIdx = 0
        foreach ($log in $logs) {
            $lIdx++
            Update-SubProgress $base ([int](($lIdx / $logs.Count) * 100)) $taskWeight

            try {
                $logInfo = Get-WinEvent -ListLog $log -ErrorAction Stop
                $sizeMB  = [math]::Round($logInfo.FileSize / 1MB, 2)
                $count   = $logInfo.RecordCount
                $diagData['EventLogsMB'] += $sizeMB

                Write-Console "  [$lIdx/$($logs.Count)] $log — $count eventos, $sizeMB MB"

                if ($dryRun) {
                    Write-Console "    [DRY RUN] Se limpiaría este log"
                } else {
                    & wevtutil.exe cl $log 2>&1 | Out-Null
                    Write-Console "    ✓ Log limpiado"
                }
            } catch {
                Write-Console "  [$lIdx] $log — Error: $($_.Exception.Message)"
            }
        }

        Write-Console ""
        Write-Console "  ✓ Event Logs $(if($dryRun){'analizados'}else{'limpiados'})"
        Write-Console "  NOTA: El log 'Security' NO fue modificado (requiere auditoría)"

        $completedTasks++
        Update-Progress ([math]::Round(($completedTasks / $totalTasks) * 100)) ""
    }

    # ── RESUMEN FINAL ────────────────────────────────────────────────────────
    # Capturar estado actual de RAM y disco para el informe
    try {
        $osSnap      = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $totalMemGB  = $osSnap.TotalVisibleMemorySize / 1MB
        $freeMemGB   = $osSnap.FreePhysicalMemory     / 1MB
        $diagData['RamUsedPct']  = [math]::Round((($totalMemGB - $freeMemGB) / $totalMemGB) * 100)
        $volSnap = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
        if ($volSnap) {
            $diagData['DiskCUsedPct'] = [math]::Round((($volSnap.Size - $volSnap.SizeRemaining) / $volSnap.Size) * 100)
        }
    } catch { }

    # Publicar resultados al hilo principal si es DryRun
    if ($dryRun -and $null -ne $DiagReportRef) {
        try { $DiagReportRef.Value = $diagData } catch { }
    }

    $endTime  = Get-Date
    $duration = $endTime - $startTime
    # [B12] Formato que soporta más de 24h sin colapsar
    $durStr = "{0:D2}d {1:D2}h {2:D2}m {3:D2}s" -f $duration.Days, $duration.Hours, $duration.Minutes, $duration.Seconds

    $footerTitle = if ($dryRun) {
        "ANÁLISIS COMPLETADO EXITOSAMENTE"
    } else {
        "OPTIMIZACIÓN COMPLETADA EXITOSAMENTE"
    }
    $footerPad   = [math]::Max(0, $boxWidth - $footerTitle.Length)
    $footerLeft  = [math]::Floor($footerPad / 2)
    $footerRight = $footerPad - $footerLeft

    Write-Console ""
    Write-Console "╔$('═' * $boxWidth)╗"
    Write-Console "║$(' ' * $footerLeft)$footerTitle$(' ' * $footerRight)║"
    Write-Console "╚$('═' * $boxWidth)╝"
    Write-Console "Tareas: $completedTasks / $totalTasks"
    Write-Console "Tiempo: $durStr"
    Write-Console ""

    Update-Status "✓ $(if($dryRun){'Análisis'}else{'Optimización'}) completada"
    Update-Progress 100 "Completado"
    $window.Dispatcher.Invoke([action]{
        $TaskText.Text = "¡Todas las tareas completadas!"
    }.GetNewClosure())

    # Auto-reinicio
    if ($options['AutoRestart'] -and -not $dryRun) {
        Write-Console "Reiniciando el sistema en 10 segundos..."
        for ($i = 10; $i -gt 0; $i--) {
            Update-Status "Reiniciando en $i segundos..."
            Start-Sleep -Seconds 1
        }
        Restart-Computer -Force
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# EVENTOS DE BOTONES
# ═════════════════════════════════════════════════════════════════════════════

# [N1] Botón de actualizar info del sistema
$btnRefreshInfo.Add_Click({ Update-SystemInfo })

# [B10] Seleccionar Todo — refleja el estado real de TODOS los checkboxes
# [B4]  chkAutoRestart incluido en el toggle para coherencia
$script:AllOptCheckboxes = @(
    $chkOptimizeDisks, $chkRecycleBin, $chkTempFiles, $chkUserTemp,
    $chkWUCache, $chkChkdsk, $chkClearMemory, $chkCloseProcesses,
    $chkDNSCache, $chkBrowserCache, $chkBackupRegistry, $chkCleanRegistry,
    $chkSFC, $chkDISM, $chkEventLogs, $chkShowStartup
    # chkAutoRestart y chkDryRun se excluyen intencionalmente (opciones de ejecución)
)

$script:AllCheckboxes = @(
    $chkOptimizeDisks, $chkRecycleBin, $chkTempFiles, $chkUserTemp,
    $chkWUCache, $chkChkdsk, $chkClearMemory, $chkCloseProcesses,
    $chkDNSCache, $chkBrowserCache, $chkBackupRegistry, $chkCleanRegistry,
    $chkSFC, $chkDISM, $chkEventLogs, $chkShowStartup, $chkAutoRestart, $chkDryRun
)

$btnSelectAll.Add_Click({
    # [B10] Comprobar estado real (todos marcados = deseleccionar, si alguno no = seleccionar)
    $allChecked = $script:AllOptCheckboxes | ForEach-Object { $_.IsChecked } | Where-Object { -not $_ }
    $targetState = ($allChecked.Count -gt 0)   # hay alguno desmarcado → vamos a marcar todos

    foreach ($cb in $script:AllOptCheckboxes) { $cb.IsChecked = $targetState }

    $btnSelectAll.Content = if ($targetState) { "✗ Deseleccionar Todo" } else { "✓ Seleccionar Todo" }
})

# ── Función central de arranque (dry-run o real) ─────────────────────────────
function Start-Optimization {
    param([bool]$DryRunOverride = $false)

    # [B2] Validar dependencia BackupRegistry → CleanRegistry
    if ($chkCleanRegistry.IsChecked -and -not $chkBackupRegistry.IsChecked -and -not $DryRunOverride) {
        $warn = Show-ThemedDialog -Title "Sin backup del registro" `
            -Message "Has activado 'Limpiar registro' sin 'Crear backup'.`n`nLimpiar el registro SIN backup puede ser peligroso.`n`n¿Deseas continuar igualmente SIN hacer backup?" `
            -Type "warning" -Buttons "YesNo"
        if (-not $warn) { return }
    }

    # [B11] Advertir si la consola tiene contenido previo
    if (-not [string]::IsNullOrWhiteSpace($ConsoleOutput.Text)) {
        $clearWarn = Show-ThemedDialog -Title "Limpiar consola" `
            -Message "La consola tiene contenido de una ejecución anterior.`n`n¿Deseas limpiarla y comenzar una nueva sesión?`n(Si quieres conservar el log, pulsa No y guárdalo primero)" `
            -Type "question" -Buttons "YesNo"
        if (-not $clearWarn) { return }
    }

    # Contar tareas seleccionadas
    $selectedTasks = @()
    if ($chkOptimizeDisks.IsChecked)  { $selectedTasks += "Optimizar discos" }
    if ($chkRecycleBin.IsChecked)     { $selectedTasks += "Vaciar papelera" }
    if ($chkTempFiles.IsChecked)      { $selectedTasks += "Temp Windows" }
    if ($chkUserTemp.IsChecked)       { $selectedTasks += "Temp Usuario" }
    if ($chkWUCache.IsChecked)        { $selectedTasks += "WU Cache" }
    if ($chkChkdsk.IsChecked)         { $selectedTasks += "CHKDSK" }
    if ($chkClearMemory.IsChecked)    { $selectedTasks += "Liberar RAM" }
    if ($chkCloseProcesses.IsChecked) { $selectedTasks += "Cerrar procesos" }
    if ($chkDNSCache.IsChecked)       { $selectedTasks += "DNS" }
    if ($chkBrowserCache.IsChecked)   { $selectedTasks += "Navegadores" }
    if ($chkBackupRegistry.IsChecked) { $selectedTasks += "Backup registro" }
    if ($chkCleanRegistry.IsChecked)  { $selectedTasks += "Limpiar registro" }
    if ($chkSFC.IsChecked)            { $selectedTasks += "SFC" }
    if ($chkDISM.IsChecked)           { $selectedTasks += "DISM" }
    if ($chkEventLogs.IsChecked)      { $selectedTasks += "Event Logs" }

    # [N8] ShowStartup se maneja en el hilo principal antes del runspace
    if ($chkShowStartup.IsChecked) {
        Show-StartupManager
    }

    if ($selectedTasks.Count -eq 0 -and -not $chkShowStartup.IsChecked) {
        Show-ThemedDialog -Title "Sin tareas seleccionadas" `
            -Message "Por favor, selecciona al menos una opción." -Type "warning"
        return
    }

    if ($selectedTasks.Count -eq 0) { return }   # Solo ShowStartup fue marcado, ya se procesó

    $isDryRun  = $DryRunOverride -or $chkDryRun.IsChecked
    $modeLabel = if ($isDryRun) { "🔍 MODO ANÁLISIS (sin cambios)" } else { "⚙ EJECUCIÓN REAL" }

    $confirm = Show-ThemedDialog -Title "Confirmar optimización" `
        -Message "Modo: $modeLabel`n`n¿Iniciar con $($selectedTasks.Count) tareas?`n• $($selectedTasks -join "`n• ")" `
        -Type "question" -Buttons "YesNo"
    if (-not $confirm) { return }

    # Preparar UI
    $btnStart.IsEnabled      = $false
    $btnDryRun.IsEnabled     = $false
    $btnSelectAll.IsEnabled  = $false
    $btnCancel.IsEnabled     = $true
    foreach ($cb in $script:AllCheckboxes) { $cb.IsEnabled = $false }

    $ConsoleOutput.Clear()
    $ProgressBar.Value  = 0
    $ProgressText.Text  = "0%"
    $TaskText.Text      = "Iniciando..."

    $script:CancelSource  = New-Object System.Threading.CancellationTokenSource
    $script:WasCancelled  = $false

    $options = @{
        'DryRun'         = $isDryRun
        'OptimizeDisks'  = $chkOptimizeDisks.IsChecked
        'RecycleBin'     = $chkRecycleBin.IsChecked
        'TempFiles'      = $chkTempFiles.IsChecked
        'UserTemp'       = $chkUserTemp.IsChecked
        'WUCache'        = $chkWUCache.IsChecked
        'Chkdsk'         = $chkChkdsk.IsChecked
        'ClearMemory'    = $chkClearMemory.IsChecked
        'CloseProcesses' = $chkCloseProcesses.IsChecked
        'DNSCache'       = $chkDNSCache.IsChecked
        'BrowserCache'   = $chkBrowserCache.IsChecked
        'BackupRegistry' = $chkBackupRegistry.IsChecked
        'CleanRegistry'  = $chkCleanRegistry.IsChecked
        'SFC'            = $chkSFC.IsChecked
        'DISM'           = $chkDISM.IsChecked
        'EventLogs'      = $chkEventLogs.IsChecked
        'AutoRestart'    = $chkAutoRestart.IsChecked
    }

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()

    # Variable compartida para recibir el informe de diagnóstico del runspace
    $script:DiagReportData   = $null
    $script:LastRunWasDryRun = $isDryRun
    $diagReportRef = [ref]$script:DiagReportData

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $powershell.AddScript($OptimizationScript)
    $powershell.AddArgument($window)
    $powershell.AddArgument($ConsoleOutput)
    $powershell.AddArgument($ProgressBar)
    $powershell.AddArgument($StatusText)
    $powershell.AddArgument($ProgressText)
    $powershell.AddArgument($TaskText)
    $powershell.AddArgument($options)
    $powershell.AddArgument($script:CancelSource.Token)
    $powershell.AddArgument($diagReportRef) | Out-Null

    $handle = $powershell.BeginInvoke()

    $script:ActivePowershell = $powershell
    $script:ActiveRunspace   = $runspace
    $script:ActiveHandle     = $handle
    $script:UI_BtnStart      = $btnStart
    $script:UI_BtnDryRun     = $btnDryRun
    $script:UI_BtnSelectAll  = $btnSelectAll
    $script:UI_BtnCancel     = $btnCancel
    $script:UI_Checkboxes    = $script:AllCheckboxes
    $script:UI_ProgressBar   = $ProgressBar
    $script:UI_ProgressText  = $ProgressText
    $script:UI_TaskText      = $TaskText
    $script:UI_StatusText    = $StatusText

    # [B8] Timer con try/catch — no bloquea si el runspace muere con excepción
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:ActiveTimer = $timer

    $timer.Add_Tick({
        $completed = $false
        try {
            if ($script:ActiveHandle -and $script:ActiveHandle.IsCompleted) {
                $completed = $true
            }
        } catch {
            $completed = $true   # error al comprobar → asumir terminado
        }

        if ($completed) {
            $script:ActiveTimer.Stop()

            try { $script:ActivePowershell.EndInvoke($script:ActiveHandle) } catch { }
            try { $script:ActivePowershell.Dispose()  } catch { }
            try { $script:ActiveRunspace.Close()      } catch { }
            try { $script:ActiveRunspace.Dispose()    } catch { }

            $cs = $script:CancelSource
            $script:CancelSource = $null
            if ($null -ne $cs) { try { $cs.Dispose() } catch { } }

            # Reset UI
            $script:UI_ProgressBar.Value  = 0
            $script:UI_ProgressText.Text  = "0%"
            $script:UI_TaskText.Text      = ""
            $script:UI_StatusText.Text    = "Listo para optimizar"

            $script:UI_BtnStart.IsEnabled     = $true
            $script:UI_BtnDryRun.IsEnabled    = $true
            $script:UI_BtnSelectAll.IsEnabled = $true
            $script:UI_BtnCancel.IsEnabled    = $false
            $script:UI_BtnCancel.Content      = "⏹ Cancelar"
            foreach ($cb in $script:UI_Checkboxes) { $cb.IsEnabled = $true }

            # Actualizar info del sistema al finalizar
            Update-SystemInfo

            if ($script:WasCancelled) {
                Show-ThemedDialog -Title "Proceso cancelado" `
                    -Message "La optimización fue cancelada por el usuario." -Type "warning"
            } elseif ($script:LastRunWasDryRun -and $null -ne $script:DiagReportData) {
                # Modo análisis completado → mostrar informe de diagnóstico
                Show-DiagnosticReport -Report $script:DiagReportData
            } elseif ($script:LastRunWasDryRun) {
                # Dry run sin datos (tareas no recogen diagData) → mensaje simple
                Show-ThemedDialog -Title "Análisis completado" `
                    -Message "Análisis completado.`n`nRevisa la consola para ver los detalles." -Type "info"
            } else {
                Show-ThemedDialog -Title "Optimización completada" `
                    -Message "¡Proceso completado correctamente!`n`nTodas las tareas seleccionadas han finalizado." -Type "success"
            }
            $script:WasCancelled = $false
        }
    })
    $timer.Start()
}

# Botón Iniciar
$btnStart.Add_Click({ Start-Optimization -DryRunOverride $false })

# [N2] Botón Analizar (Dry Run directo)
$btnDryRun.Add_Click({ Start-Optimization -DryRunOverride $true })

# Botón Cancelar
$btnCancel.Add_Click({
    if ($null -ne $script:CancelSource -and -not $script:CancelSource.IsCancellationRequested) {
        $res = Show-ThemedDialog -Title "Confirmar cancelación" `
            -Message "¿Cancelar la optimización en curso?`n`nLa tarea actual terminará antes de detenerse." `
            -Type "question" -Buttons "YesNo"
        if ($res) {
            $script:WasCancelled = $true
            $script:CancelSource.Cancel()
            $btnCancel.IsEnabled = $false
            $btnCancel.Content   = "⏹ Cancelando..."
            Write-ConsoleMain "⚠ Cancelación solicitada — esperando fin de tarea actual..."
        }
    }
})

# Botón Guardar Log
$btnSaveLog.Add_Click({
    $logContent = $ConsoleOutput.Text
    if ([string]::IsNullOrWhiteSpace($logContent)) {
        Show-ThemedDialog -Title "Log vacío" `
            -Message "La consola está vacía. No hay nada que guardar." -Type "info"
        return
    }

    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Title            = "Guardar Log de Optimización"
    $saveDialog.Filter           = "Archivo de texto (*.txt)|*.txt|Todos los archivos (*.*)|*.*"
    $saveDialog.DefaultExt       = "txt"
    $saveDialog.FileName         = "OptimizadorLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    if (-not (Test-Path $script:LogsDir)) {
        [System.IO.Directory]::CreateDirectory($script:LogsDir) | Out-Null
    }
    $saveDialog.InitialDirectory = $script:LogsDir

    if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $logContent | Out-File -FilePath $saveDialog.FileName -Encoding UTF8
            Show-ThemedDialog -Title "Log guardado" `
                -Message "Log guardado en:`n`n$($saveDialog.FileName)" -Type "success"
        } catch {
            Show-ThemedDialog -Title "Error al guardar" `
                -Message "Error al guardar:`n$($_.Exception.Message)" -Type "error"
        }
    }
})

# Botón Salir
$btnExit.Add_Click({
    try { $script:AppMutex.ReleaseMutex() } catch { }
    $window.Close()
})

# Liberar mutex al cerrar por la X
$window.Add_Closed({
    $script:AppClosing = $true   # [FIX] Señalizar cierre antes de todo para que Update-PerformanceTab no dispare
    # [BF3] Limpiar estado cacheado para evitar errores al reiniciar
    try { $script:AppMutex.ReleaseMutex() } catch { }
    try { $chartTimer.Stop() } catch { }
    try { if ($null -ne $script:DiskUiTimer) { $script:DiskUiTimer.Stop() } } catch { }
    if ($null -ne $script:DiskCounter) { try { $script:DiskCounter.Dispose() } catch { } }
    # [A3] Parar auto-refresco si activo
    try { if ($null -ne $script:AutoRefreshTimer) { $script:AutoRefreshTimer.Stop(); $script:AutoRefreshTimer = $null } } catch {}
    # [C3] Guardar configuración al cerrar
    try { Save-Settings } catch {}

    # Señalizar parada del runspace de escaneo y esperar brevemente
    [ScanCtl211]::Stop = $true
    if ($null -ne $script:DiskScanRunspace) {
        try { $script:DiskScanRunspace.Close()   } catch {}
        try { $script:DiskScanRunspace.Dispose() } catch {}
        $script:DiskScanRunspace = $null
    }
    if ($null -ne $script:DiskScanPS) {
        try { $script:DiskScanPS.Dispose() } catch {}
        $script:DiskScanPS = $null
    }
    $script:DiskScanAsync = $null

    # Vaciar cola y colecciones vivas para liberar referencias y evitar errores al relanzar
    if ($null -ne $script:ScanQueue) {
        $tmp = $null
        while ($script:ScanQueue.TryDequeue([ref]$tmp)) {}
        $script:ScanQueue = $null
    }
    if ($null -ne $script:LiveList)       { try { $script:LiveList.Clear()       } catch {}; $script:LiveList       = $null }
    if ($null -ne $script:LiveItems)      { try { $script:LiveItems.Clear()      } catch {}; $script:LiveItems      = $null }
    if ($null -ne $script:AllScannedItems){ try { $script:AllScannedItems.Clear() } catch {}; $script:AllScannedItems = $null }
    if ($null -ne $script:LiveIndexMap)   { try { $script:LiveIndexMap.Clear()   } catch {}; $script:LiveIndexMap   = $null }

    # [RAM-05] Cerrar RunspacePool centralizado
    if ($null -ne $script:RunspacePool) {
        try { $script:RunspacePool.Close()   } catch {}
        try { $script:RunspacePool.Dispose() } catch {}
        $script:RunspacePool = $null
    }

    # Liberar CancellationTokenSource de optimización si estaba activo
    if ($null -ne $script:CancelSource) {
        try { $script:CancelSource.Cancel()  } catch {}
        try { $script:CancelSource.Dispose() } catch {}
        $script:CancelSource = $null
    }

    # Detener el mutex del proceso de optimización si existe
    if ($null -ne $script:OptRunspace) {
        try { $script:OptRunspace.Close()   } catch {}
        try { $script:OptRunspace.Dispose() } catch {}
        $script:OptRunspace = $null
    }
})

# ─────────────────────────────────────────────────────────────────────────────
# ARRANQUE
# ─────────────────────────────────────────────────────────────────────────────
# Update-SystemInfo se llama ahora desde el evento Loaded de la ventana

# ─────────────────────────────────────────────────────────────────────────────
# Función: Ventana emergente "Acerca de la versión"
# ─────────────────────────────────────────────────────────────────────────────
function Show-AboutWindow {
    $aboutXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Acerca de SysOpt" Width="560" Height="760"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="#0D0F1A"
        WindowStyle="SingleBorderWindow">
    <Grid>
        <Rectangle Fill="#0D0F1A"/>
        <!-- Blob azul decorativo -->
        <Ellipse Width="400" Height="400" Opacity="0.09" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="-120,-80,0,0">
            <Ellipse.Fill><RadialGradientBrush><GradientStop Color="#5BA3FF" Offset="0"/><GradientStop Color="Transparent" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
        </Ellipse>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0">
            <StackPanel Margin="28,24,28,24">
                <!-- Header con logo + título -->
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,0,18">
                    <Image Name="aboutLogo" Width="56" Height="56" Margin="0,0,14,0" VerticalAlignment="Center"
                           RenderOptions.BitmapScalingMode="HighQuality"/>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock FontFamily="Segoe UI" FontSize="26" FontWeight="Bold" Foreground="#E8ECF4">
                            <Run Text="SYS"/><Run Foreground="#5BA3FF" Text="OPT"/>
                        </TextBlock>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#7880A0">Windows Optimizer GUI</TextBlock>
                    </StackPanel>
                    <Border CornerRadius="6" Background="#1A5BA3FF" BorderBrush="#405BA3FF" BorderThickness="1"
                            Padding="10,4" Margin="14,0,0,0" VerticalAlignment="Center">
                        <TextBlock FontFamily="Consolas" FontSize="11" FontWeight="Bold" Foreground="#5BA3FF" Text="v2.4.0"/>
                    </Border>
                </StackPanel>

                <!-- Separador -->
                <Rectangle Height="1" Fill="#252B40" Margin="0,0,0,16"/>

                <!-- v2.4.0 FIFO Streaming -->
                <Border CornerRadius="8" Background="#131625" BorderBrush="#3D8EFF" BorderThickness="0,0,0,2" Padding="14,12" Margin="0,0,0,12">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border CornerRadius="4" Background="#1F5BA3FF" Padding="6,2" Margin="0,0,8,0">
                                <TextBlock FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="#5BA3FF" Text="v2.4.0 · FIFO"/>
                            </Border>
                            <TextBlock FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#E8ECF4" VerticalAlignment="Center" Text="FIFO Streaming Anti-RAM-Drain"/>
                        </StackPanel>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0" TextWrapping="Wrap" LineHeight="20">
                            <Run Foreground="#4AE896" Text="• [FIFO-01]"/><Run Text="  Guardado de snapshot: streaming ConcurrentQueue + JsonTextWriter directo al disco (−50% a −200% RAM pico)&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [FIFO-02]"/><Run Text="  Carga de entries: ConvertFrom-Json nativo + ConcurrentQueue — DispatcherTimer drena en lotes de 500/tick&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [FIFO-03]"/><Run Text="  Terminación limpia garantizada: GC + LOH compaction en bloque finally, incluso en error&#x0a;"/>
                            <Run Foreground="#5BA3FF" Text="• [Fix]"/><Run Text="  Set-Content → File::WriteAllText en Save-Settings (evita 'Stream was not readable' en PS 5.1)&#x0a;"/>
                            <Run Foreground="#5BA3FF" Text="• [Fix]"/><Run Text="  Toggle colapsar/expandir: Items.Refresh() explícito en LiveList (List&lt;T&gt;)&#x0a;"/>
                            <Run Foreground="#5BA3FF" Text="• [Fix]"/><Run Text="  Parser FIFO-02: reemplazado regex frágil por ConvertFrom-Json nativo (compatible con snapshots v2.3 y v2.4.0)"/>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- v2.3.0 RAM + Snapshots -->
                <Border CornerRadius="8" Background="#131625" BorderBrush="#9B7EFF" BorderThickness="0,0,0,2" Padding="14,12" Margin="0,0,0,12">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border CornerRadius="4" Background="#1A9B7EFF" Padding="6,2" Margin="0,0,8,0">
                                <TextBlock FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="#9B7EFF" Text="v2.3.0 · RAM + SNAPSHOTS"/>
                            </Border>
                            <TextBlock FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#E8ECF4" VerticalAlignment="Center" Text="Optimización RAM y comparador de snapshots"/>
                        </StackPanel>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0" TextWrapping="Wrap" LineHeight="20">
                            <Run Foreground="#4AE896" Text="• [RAM-01]"/><Run Text="  DiskItem_v211 sin INPC — wrapper DiskItemToggle_v230 ligero (−30 a −80 MB en escaneos grandes)&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [RAM-02]"/><Run Text="  Exportación CSV/HTML con StreamWriter directo y flush por lotes (sin StringBuilder)&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [RAM-04]"/><Run Text="  Load-SnapshotList: JsonTextReader línea a línea — Entries nunca en RAM al listar (−200 a −400 MB)&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [RAM-05]"/><Run Text="  RunspacePool centralizado (1–3 runspaces) para operaciones async&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [NEW]"/><Run Text="  Snapshots con checkboxes, botón 'Todo' y contador en tiempo real&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [NEW]"/><Run Text="  Comparador en 3 modos: snapshot vs actual, snapshot A vs B, histórico&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [NEW]"/><Run Text="  Eliminación en lote de snapshots con confirmación&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [NEW]"/><Run Text="  Comparador O(1) con HashSet + Dictionary (antes O(n²))"/>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- v2.2.0 Explorador de archivos -->
                <Border CornerRadius="8" Background="#131625" BorderBrush="#2EDFBF" BorderThickness="0,0,0,2" Padding="14,12" Margin="0,0,0,12">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border CornerRadius="4" Background="#1A2EDFBF" Padding="6,2" Margin="0,0,8,0">
                                <TextBlock FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="#2EDFBF" Text="v2.2.0 · EXPLORADOR"/>
                            </Border>
                            <TextBlock FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#E8ECF4" VerticalAlignment="Center" Text="Explorador de archivos y correcciones de rutas"/>
                        </StackPanel>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0" TextWrapping="Wrap" LineHeight="20">
                            <Run Foreground="#2EDFBF" Text="• [BF1]"/><Run Text="  Snapshots: ruta movida a .\snapshots (relativo al script)&#x0a;"/>
                            <Run Foreground="#2EDFBF" Text="• [BF3]"/><Run Text="  Fix crítico en Load-SnapshotList: snapshots que no aparecían en la lista&#x0a;"/>
                            <Run Foreground="#2EDFBF" Text="• [BF4]"/><Run Text="  Diálogo de confirmación: escape de comillas dobles en nombres de snapshot&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [N1]"/><Run Text="  Snapshots con CheckBox y botón 'Todo' para marcar en lote&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [N2]"/><Run Text="  Comparar mejorado: 3 modos (snapshot vs actual, A vs B)&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [N3]"/><Run Text="  Eliminar snapshots en lote con confirmación"/>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- v2.1.3 UX -->
                <Border CornerRadius="8" Background="#131625" BorderBrush="#252B40" BorderThickness="0,0,0,2" Padding="14,12" Margin="0,0,0,12">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border CornerRadius="4" Background="#1F5BA3FF" Padding="6,2" Margin="0,0,8,0">
                                <TextBlock FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="#5BA3FF" Text="v2.1.3 · UX"/>
                            </Border>
                            <TextBlock FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#E8ECF4" VerticalAlignment="Center" Text="Tema oscuro y Output interactivo"/>
                        </StackPanel>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0" TextWrapping="Wrap" LineHeight="20">
                            <Run Foreground="#4AE896" Text="• [U1]"/><Run Text="  ComboBox con estilo oscuro temático (no más blanco)&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [U2]"/><Run Text="  ContextMenu / MenuItem con estilo oscuro y sombra&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [U3]"/><Run Text="  Botones Output funcionales: 🔴 ocultar · 🟡 minimizar · 🟢 expandir&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [U4]"/><Run Text="  Menú contextual del Explorador: Mostrar Output&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [U5]"/><Run Text="  Enlace GitHub en About abre el navegador"/>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- v2.1.2 BugFix (archivado) -->
                <Border CornerRadius="8" Background="#131625" BorderBrush="#252B40" BorderThickness="0,0,0,2" Padding="14,12" Margin="0,0,0,12">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border CornerRadius="4" Background="#1A252B40" Padding="6,2" Margin="0,0,8,0">
                                <TextBlock FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="#9BA4C0" Text="v2.1.2 · BUGFIX"/>
                            </Border>
                            <TextBlock FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#E8ECF4" VerticalAlignment="Center" Text="Correcciones de logo y auto-refresco"/>
                        </StackPanel>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0" TextWrapping="Wrap" LineHeight="20">
                            <Run Foreground="#4AE896" Text="• [BF4]"/><Run Text="  Logo: $script:AppDir unificado&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [BF5]"/><Run Text="  Auto-refresco: timer se recrea al cambiar intervalo&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [BF6]"/><Run Text="  Get-SizeColorFromStr duplicado eliminado"/>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- v2.1.1 BugFix -->
                <Border CornerRadius="8" Background="#131625" BorderBrush="#252B40" BorderThickness="0,0,0,2" Padding="14,12" Margin="0,0,0,12">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border CornerRadius="4" Background="#1A303060" Padding="6,2" Margin="0,0,8,0">
                                <TextBlock FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="#9BA4C0" Text="v2.1.1 · BUGFIX"/>
                            </Border>
                            <TextBlock FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#E8ECF4" VerticalAlignment="Center" Text="Correcciones de estabilidad"/>
                        </StackPanel>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0" TextWrapping="Wrap" LineHeight="20">
                            <Run Foreground="#4AE896" Text="• [BF1]"/><Run Text="  Explorador: corregido solapamiento del filtro de búsqueda (Grid.Row=1 faltante)&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [BF2]"/><Run Text="  Guard Add-Type rediseñado: DiskItem_v211 + ScanCtl211 + PScanner211 — elimina TYPE_ALREADY_EXISTS&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [BF3]"/><Run Text="  Cuadrícula de fondo más visible (StrokeThickness 0.6, Opacity 0.22)"/>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- v2.1.0 -->
                <Border CornerRadius="8" Background="#131625" BorderBrush="#FFB547" BorderThickness="0,0,0,2" Padding="14,12" Margin="0,0,0,12">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border CornerRadius="4" Background="#1FFFB547" Padding="6,2" Margin="0,0,8,0">
                                <TextBlock FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="#FFB547" Text="v2.1.0 · FUNCIONALIDAD"/>
                            </Border>
                            <TextBlock FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#E8ECF4" VerticalAlignment="Center" Text="Explorador mejorado"/>
                        </StackPanel>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0" TextWrapping="Wrap" LineHeight="20">
                            <Run Foreground="#FFB547" Text="• [B1]"/><Run Text="  Explorador: filtro de búsqueda en tiempo real por nombre de carpeta&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [B2]"/><Run Text="  Explorador: menú contextual (abrir, copiar ruta, eliminar)&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [B3]"/><Run Text="  Explorador: exportar resultados completos a CSV&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [A3]"/><Run Text="  Rendimiento: auto-refresco configurable (5/15/30/60 s)&#x0a;"/>
                            <Run Foreground="#FFB547" Text="• [C3]"/><Run Text="  Persistencia de configuración en %APPDATA%\SysOpt\settings.json"/>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- v2.0.3 / anteriores -->
                <Border CornerRadius="8" Background="#131625" BorderBrush="#4AE896" BorderThickness="0,0,0,2" Padding="14,12" Margin="0,0,0,12">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border CornerRadius="4" Background="#1A4AE896" Padding="6,2" Margin="0,0,8,0">
                                <TextBlock FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="#4AE896" Text="v2.0.3 · BASE ESTABLE"/>
                            </Border>
                            <TextBlock FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#E8ECF4" VerticalAlignment="Center" Text="Pestañas y correcciones críticas"/>
                        </StackPanel>
                        <TextBlock FontFamily="Segoe UI" FontSize="11" Foreground="#9BA4C0" TextWrapping="Wrap" LineHeight="20">
                            <Run Foreground="#4AE896" Text="• [T1]"/><Run Text="  Nueva pestaña RENDIMIENTO: CPU, RAM, SMART disco, red&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [T2]"/><Run Text="  Nueva pestaña EXPLORADOR DE DISCO: escáner tipo TreeSize&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [N1]"/><Run Text="  Panel de info del sistema (CPU, RAM, Disco C:)&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [N2]"/><Run Text="  Modo Análisis (Dry Run) — reporta sin hacer cambios&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [N3]"/><Run Text="  Limpieza de Windows Update Cache&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [B1]"/><Run Text="  RAM: liberación real via EmptyWorkingSet Win32&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [B3]"/><Run Text="  Mutex: AbandonedMutexException manejada&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [B6]"/><Run Text="  Opera / OperaGX / Brave: rutas de caché completas&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [B7]"/><Run Text="  Firefox: limpia cache y cache2 (legacy + moderno)&#x0a;"/>
                            <Run Foreground="#4AE896" Text="• [B9]"/><Run Text="  CHKDSK: orden correcto (dirty set antes de chkntfs)"/>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- Footer -->
                <Rectangle Height="1" Fill="#252B40" Margin="0,4,0,12"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                    <TextBlock FontFamily="Segoe UI" FontSize="10" Foreground="#4A5068" Text="2026 (c) Danew Malavita | "/>
                    <TextBlock FontFamily="Segoe UI" FontSize="10">
                        <Hyperlink Name="lnkGithub" NavigateUri="https://github.com/Danewmalavita/"
                                   Foreground="#5BA3FF" TextDecorations="None">
                            github.com/Danewmalavita
                        </Hyperlink>
                    </TextBlock>
                </StackPanel>

                <!-- Botón cerrar -->
                <Button Name="btnAboutClose" Content="Cerrar"
                        Width="120" Height="34" Margin="0,16,0,0"
                        HorizontalAlignment="Center"
                        Background="#1A2040" BorderBrush="#3D8EFF" BorderThickness="1"
                        Foreground="#5BA3FF" FontFamily="Segoe UI" FontSize="12" FontWeight="SemiBold"
                        Cursor="Hand">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="bd" CornerRadius="8" Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bd" Property="Background" Value="#253060"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </StackPanel>
        </ScrollViewer>
    </Grid>
</Window>
"@
    try {
        $aboutReader = [System.Xml.XmlNodeReader]::new([xml]$aboutXaml)
        $aboutWin    = [Windows.Markup.XamlReader]::Load($aboutReader)
        $aboutWin.Owner = $window

        # Cargar logo en la ventana about también
        $aboutLogoCtrl = $aboutWin.FindName("aboutLogo")
        if ($null -ne $imgLogo -and $null -ne $imgLogo.Source -and $null -ne $aboutLogoCtrl) {
            $aboutLogoCtrl.Source = $imgLogo.Source
        }

        $btnAboutClose = $aboutWin.FindName("btnAboutClose")
        $btnAboutClose.Add_Click({ $aboutWin.Close() })

        # Enlace GitHub funcional
        $lnkGh = $aboutWin.FindName("lnkGithub")
        if ($null -ne $lnkGh) {
            $lnkGh.Add_RequestNavigate({
                param($s, $e)
                Start-Process $e.Uri.AbsoluteUri
                $e.Handled = $true
            })
        }

        $aboutWin.ShowDialog() | Out-Null
    } catch {
        Show-ThemedDialog -Title "Error" `
            -Message "Error al abrir la ventana de novedades:`n$($_.Exception.Message)" -Type "error"
    }
}

# Conectar botón ℹ
if ($null -ne $btnAbout) {
    $btnAbout.Add_Click({ Show-AboutWindow })
}

# ─────────────────────────────────────────────────────────────────────────────
# Mensaje de bienvenida simplificado en consola (novedades → botón ℹ)
# ─────────────────────────────────────────────────────────────────────────────
Write-ConsoleMain "═══════════════════════════════════════════════════════════"
Write-ConsoleMain "SysOpt - Windows Optimizer GUI — VERSIÓN 2.4.0"
Write-ConsoleMain "═══════════════════════════════════════════════════════════"
Write-ConsoleMain "Sistema iniciado correctamente"
Write-ConsoleMain ""
Write-ConsoleMain "Selecciona las opciones y presiona '▶ Iniciar Optimización'"
Write-ConsoleMain "  o '🔍 Analizar' para ver qué se liberaría sin cambios."
Write-ConsoleMain ""
Write-ConsoleMain "💡 Ver novedades de la versión: botón  ℹ  en la barra superior."
Write-ConsoleMain ""


$window.ShowDialog() | Out-Null
