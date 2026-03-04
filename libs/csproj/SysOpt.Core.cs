// =============================================================================
// SysOpt.Core — v3.2.0
// Motor de idiomas · XAML loader · Settings · DAL · CTK · Agent hooks
//
// Compilar (NET 4.x / PowerShell 5.1):
//   csc /target:library /out:SysOpt.Core.dll SysOpt.Core.cs
//       /r:System.dll /r:System.Core.dll /r:System.Management.dll
//
// Compilar (.NET 6+):
//   dotnet build  (requiere proyecto .csproj con TargetFramework=net6.0-windows)
// =============================================================================

using System;
using System.Collections.Generic;
using System.IO;
using System.Management;          // WMI — System.Management.dll
using System.Diagnostics;         // PerformanceCounter, Process
using System.Net.NetworkInformation; // NetworkInterface
using System.Net;                  // IPGlobalProperties (puertos abiertos)
using System.Threading;

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN 1 — EXISTENTE (sin cambios de firma, retro-compatible)
// ─────────────────────────────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════════
// LangEngine — Parsing de archivos .lang (formato INI: [meta] + [ui])
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// Loc — Minimal localization helper. PS1 calls Loc.SetDict() after loading language.
// ═══════════════════════════════════════════════════════════════════════════════
public static class Loc
{
    private static Dictionary<string, string> _d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    public static void SetDict(Dictionary<string, string> d)
    {
        _d = d ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }

    public static string T(string key, string fallback)
    {
        return (_d != null && _d.ContainsKey(key)) ? _d[key] : fallback;
    }
}

public static class LangEngine
{
    public static Dictionary<string, string> ParseLangFile(string path)
    {
        if (string.IsNullOrEmpty(path))  throw new ArgumentNullException("path");
        if (!File.Exists(path))          throw new FileNotFoundException("Lang file not found: " + path);

        var strings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string section = "";

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line[0] == '#') continue;
            if (line[0] == '[' && line[line.Length - 1] == ']')
            {
                section = line.Substring(1, line.Length - 2).ToLowerInvariant();
                continue;
            }
            if (section != "ui") continue;
            int eq = line.IndexOf('=');
            if (eq <= 0) continue;
            string key = line.Substring(0, eq).Trim();
            string val = line.Substring(eq + 1).Trim().Replace("\\n", "\n");
            // Strip surrounding quotes if present
            if (val.Length >= 2 && val[0] == '"' && val[val.Length - 1] == '"')
                val = val.Substring(1, val.Length - 2);
            strings[key] = val;
        }
        return strings;
    }

    public static Dictionary<string, string> GetLangMeta(string path)
    {
        if (string.IsNullOrEmpty(path))  throw new ArgumentNullException("path");
        if (!File.Exists(path))          throw new FileNotFoundException("Lang file not found: " + path);

        var meta = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string section = "";

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line[0] == '#') continue;
            if (line[0] == '[' && line[line.Length - 1] == ']')
            {
                section = line.Substring(1, line.Length - 2).ToLowerInvariant();
                continue;
            }
            if (section != "meta") continue;
            int eq = line.IndexOf('=');
            if (eq <= 0) continue;
            meta[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
        }
        return meta;
    }

    public static string[] ListLanguages(string langFolder)
    {
        if (!Directory.Exists(langFolder)) return new string[0];
        var files = Directory.GetFiles(langFolder, "*.lang");
        var names = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            names[i] = Path.GetFileNameWithoutExtension(files[i]);
        Array.Sort(names, StringComparer.OrdinalIgnoreCase);
        return names;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// XamlLoader — Carga de archivos .xaml externos
// ═══════════════════════════════════════════════════════════════════════════════
public static class XamlLoader
{
    public static string Load(string xamlFolder, string name)
    {
        if (string.IsNullOrEmpty(xamlFolder)) throw new ArgumentNullException("xamlFolder");
        if (string.IsNullOrEmpty(name))        throw new ArgumentNullException("name");

        string fileName = name.EndsWith(".xaml", StringComparison.OrdinalIgnoreCase)
            ? name : name + ".xaml";
        string path = Path.Combine(xamlFolder, fileName);

        if (!File.Exists(path))
            throw new FileNotFoundException("XAML file not found: " + path);

        return File.ReadAllText(path, System.Text.Encoding.UTF8);
    }

    public static string[] ListXaml(string xamlFolder)
    {
        if (!Directory.Exists(xamlFolder)) return new string[0];
        var files = Directory.GetFiles(xamlFolder, "*.xaml");
        var names = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            names[i] = Path.GetFileNameWithoutExtension(files[i]);
        Array.Sort(names, StringComparer.OrdinalIgnoreCase);
        return names;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SettingsHelper — Lectura de configuración JSON simple (sin Newtonsoft)
// ═══════════════════════════════════════════════════════════════════════════════
public static class SettingsHelper
{
    public static string ReadKey(string jsonPath, string key)
    {
        if (!File.Exists(jsonPath)) return null;
        var text   = File.ReadAllText(jsonPath);
        string search = "\"" + key + "\"";
        int idx    = text.IndexOf(search, StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return null;
        int colon  = text.IndexOf(':', idx + search.Length);
        if (colon < 0) return null;
        int start  = text.IndexOf('"', colon + 1);
        if (start < 0) return null;
        int end    = text.IndexOf('"', start + 1);
        if (end < 0) return null;
        return text.Substring(start + 1, end - start - 1);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN 2 — NUEVO: CTK (CancellationToken Manager)
// ─────────────────────────────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════════
// ScanTokenManager — CancellationToken global para todos los runspaces
//
// Reemplaza el flag booleano ScanCtl211.Stop.
// Uso en PS:
//   [ScanTokenManager]::RequestNew()          # antes de iniciar escaneo
//   [ScanTokenManager]::Token                 # pasa al runspace / task
//   [ScanTokenManager]::Cancel()              # desde botón Stop
//   [ScanTokenManager]::IsCancellationRequested  # equivale a ScanCtl211.Stop
// ═══════════════════════════════════════════════════════════════════════════════
public static class ScanTokenManager
{
    private static CancellationTokenSource _cts = new CancellationTokenSource();
    private static readonly object _lock = new object();

    /// <summary>Token actual. Pásalo a runspaces y tasks.</summary>
    public static CancellationToken Token
    {
        get { lock (_lock) { return _cts.Token; } }
    }

    /// <summary>True si se ha pedido cancelación — equivale a ScanCtl211.Stop.</summary>
    public static bool IsCancellationRequested
    {
        get { lock (_lock) { return _cts.IsCancellationRequested; } }
    }

    /// <summary>
    /// Crea un nuevo CTS limpio para una nueva operación.
    /// Llama siempre antes de iniciar un escaneo/operación larga.
    /// Cancela y libera el anterior automáticamente.
    /// </summary>
    public static void RequestNew()
    {
        lock (_lock)
        {
            try   { _cts.Cancel(); }  catch { }
            try   { _cts.Dispose(); } catch { }
            _cts = new CancellationTokenSource();
        }
    }

    /// <summary>Cancela la operación en curso. Seguro llamar varias veces.</summary>
    public static void Cancel()
    {
        lock (_lock)
        {
            try { if (!_cts.IsCancellationRequested) _cts.Cancel(); }
            catch { }
        }
    }

    /// <summary>
    /// Crea un CTS vinculado con timeout opcional.
    /// Útil para operaciones con tiempo máximo (p. ej. CimSession).
    /// </summary>
    /// <summary>
    /// Crea un CTS vinculado con timeout opcional.
    /// IMPORTANTE: El caller debe disponer el CTS retornado (.Dispose()).
    /// </summary>
    public static CancellationTokenSource GetCtsWithTimeout(int timeoutMs)
    {
        lock (_lock)
        {
            var timeoutCts = new CancellationTokenSource(timeoutMs);
            var linked = CancellationTokenSource.CreateLinkedTokenSource(
                _cts.Token, timeoutCts.Token);
            linked.Token.Register(() => { try { timeoutCts.Dispose(); } catch {} });
            return linked;
        }
    }

    /// <summary>Libera el CTS actual. Llamar en Add_Closed.</summary>
    public static void Dispose()
    {
        lock (_lock)
        {
            try { _cts.Cancel();  } catch { }
            try { _cts.Dispose(); } catch { }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN 3 — NUEVO: Data Models (POCOs puros, serializables)
// Sin dependencias de WPF ni PowerShell — válidos standalone y en agente
// ─────────────────────────────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════════
// CpuSnapshot
// ═══════════════════════════════════════════════════════════════════════════════
public class CpuSnapshot
{
    public string   Name              { get; set; }  // "Intel Core i7-12700K"
    public int      Cores             { get; set; }  // Núcleos físicos
    public int      LogicalProcessors { get; set; }  // Hilos
    public double   LoadPercent       { get; set; }  // 0-100
    public double   ClockMhz          { get; set; }  // MHz actual
    public double   MaxClockMhz       { get; set; }  // MHz máximo
    public double   TemperatureCelsius{ get; set; }  // -1 si no disponible
    public double[] CoreLoads         { get; set; }  // Un entry por core lógico
    public DateTime Timestamp         { get; set; }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RamSnapshot
// ═══════════════════════════════════════════════════════════════════════════════
public class RamSnapshot
{
    public long   TotalBytes          { get; set; }
    public long   UsedBytes           { get; set; }
    public long   FreeBytes           { get; set; }
    public double UsedPercent         { get; set; }  // 0-100
    public long   PageFileTotalBytes  { get; set; }
    public long   PageFileUsedBytes   { get; set; }
    public double PageFileUsedPercent { get; set; }
    public List<RamModuleInfo> Modules{ get; set; }
    public DateTime Timestamp         { get; set; }

    public RamSnapshot() { Modules = new List<RamModuleInfo>(); }
}

public class RamModuleInfo
{
    public string Slot         { get; set; }
    public long   CapacityBytes{ get; set; }
    public string Type         { get; set; }  // "DDR4", "DDR5"…
    public int    SpeedMhz     { get; set; }
    public string Manufacturer { get; set; }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DiskSnapshot
// ═══════════════════════════════════════════════════════════════════════════════
public class DiskSnapshot
{
    public List<DiskDriveInfo>   Drives    { get; set; }
    public List<DiskVolumeInfo>  Volumes   { get; set; }
    public double ReadBytesPerSec  { get; set; }  // _Total desde PerformanceCounter
    public double WriteBytesPerSec { get; set; }  // _Total desde PerformanceCounter
    public double ActivityPercent  { get; set; }  // % Disk Time _Total
    public DateTime Timestamp      { get; set; }

    public DiskSnapshot()
    {
        Drives  = new List<DiskDriveInfo>();
        Volumes = new List<DiskVolumeInfo>();
    }
}

public class DiskDriveInfo
{
    public string FriendlyName   { get; set; }
    public string MediaType      { get; set; }  // "SSD", "HDD"
    public string BusType        { get; set; }  // "NVMe", "SATA"
    public long   SizeBytes      { get; set; }
    public string HealthStatus   { get; set; }  // "Healthy", "Warning", "Unhealthy"
    public int    PowerOnHours   { get; set; }  // -1 si no disponible
    public int    TemperatureCelsius { get; set; } // -1 si no disponible
    public long   ReadErrorsTotal    { get; set; }
    public int    WearPercent        { get; set; } // -1 si no disponible
}

public class DiskVolumeInfo
{
    public string DeviceId       { get; set; }  // "C:"
    public string Label          { get; set; }
    public string FileSystem     { get; set; }  // "NTFS"
    public long   TotalBytes     { get; set; }
    public long   FreeBytes      { get; set; }
    public double UsedPercent    { get; set; }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NetworkSnapshot
// ═══════════════════════════════════════════════════════════════════════════════
public class NetworkSnapshot
{
    public List<NetworkAdapterInfo> Adapters { get; set; }
    public DateTime Timestamp               { get; set; }

    public NetworkSnapshot() { Adapters = new List<NetworkAdapterInfo>(); }
}

public class NetworkAdapterInfo
{
    public string Name            { get; set; }
    public string Description     { get; set; }
    public string Type            { get; set; }   // "Ethernet", "WiFi", "Virtual"
    public string MacAddress      { get; set; }
    public string IpAddress       { get; set; }
    public string Gateway         { get; set; }
    public bool   IsUp            { get; set; }
    public long   SpeedBps        { get; set; }
    public double RxBytesPerSec   { get; set; }
    public double TxBytesPerSec   { get; set; }
    public long   TotalRxBytes    { get; set; }
    public long   TotalTxBytes    { get; set; }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GpuSnapshot
// ═══════════════════════════════════════════════════════════════════════════════
public class GpuSnapshot
{
    public List<GpuInfo> Gpus { get; set; }
    public DateTime Timestamp { get; set; }

    public GpuSnapshot() { Gpus = new List<GpuInfo>(); }
}

public class GpuInfo
{
    public string Name              { get; set; }
    public string DriverVersion     { get; set; }
    public long   AdapterRamBytes   { get; set; }
    public string VideoModeDesc     { get; set; }   // "1920 x 1080 x 4294967296 colors"
    public string Status            { get; set; }   // WMI Availability field
    public double TemperatureCelsius{ get; set; }   // -1 si no disponible vía WMI básico
}

// ═══════════════════════════════════════════════════════════════════════════════
// PortSnapshot — puertos TCP/UDP abiertos
// ═══════════════════════════════════════════════════════════════════════════════
public class PortSnapshot
{
    public List<OpenPortInfo> TcpPorts { get; set; }
    public List<OpenPortInfo> UdpPorts { get; set; }
    public DateTime Timestamp          { get; set; }

    public PortSnapshot()
    {
        TcpPorts = new List<OpenPortInfo>();
        UdpPorts = new List<OpenPortInfo>();
    }
}

public class OpenPortInfo
{
    public int    LocalPort    { get; set; }
    public string LocalAddress { get; set; }
    public int    RemotePort   { get; set; }
    public string RemoteAddress{ get; set; }
    public string State        { get; set; }  // "Listen", "Established", etc.
    public int    Pid          { get; set; }
    public string ProcessName  { get; set; }  // Nombre del proceso, si disponible
}

// ═══════════════════════════════════════════════════════════════════════════════
// SystemSnapshot — contenedor completo de todos los módulos
// Es el objeto que el agente futuro serializa y envía al servidor
// ═══════════════════════════════════════════════════════════════════════════════
public class SystemSnapshot
{
    public string       MachineName { get; set; }
    public string       OsCaption   { get; set; }
    public string       OsVersion   { get; set; }
    public string       OsBuild     { get; set; }   // "22631" — extracted from Win32_OperatingSystem.BuildNumber
    public DateTime     BootTime    { get; set; }   // LastBootUpTime — uptime info
    public DateTime     Timestamp   { get; set; }

    public CpuSnapshot     Cpu      { get; set; }
    public RamSnapshot     Ram      { get; set; }
    public DiskSnapshot    Disk     { get; set; }
    public NetworkSnapshot Network  { get; set; }
    public GpuSnapshot     Gpu      { get; set; }
    public PortSnapshot    Ports    { get; set; }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN 4 — NUEVO: DAL (Data Access Layer)
// Todas las funciones devuelven POCOs puros — cero lógica de UI aquí
// ─────────────────────────────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════════
// SystemDataCollector — métodos Get-* estáticos
//
// Uso en PS (standalone):
//   $cpu  = [SystemDataCollector]::GetCpuSnapshot()
//   $ram  = [SystemDataCollector]::GetRamSnapshot()
//   $disk = [SystemDataCollector]::GetDiskSnapshot()
//   $net  = [SystemDataCollector]::GetNetworkSnapshot()
//   $gpu  = [SystemDataCollector]::GetGpuSnapshot()
//   $port = [SystemDataCollector]::GetPortSnapshot()
//   $snap = [SystemDataCollector]::GetFullSnapshot()   # todos a la vez
// ═══════════════════════════════════════════════════════════════════════════════
public static class SystemDataCollector
{
    // ── Contadores de rendimiento de disco (se inicializan lazy) ──────────
    private static PerformanceCounter _diskReadCounter;
    private static PerformanceCounter _diskWriteCounter;
    private static PerformanceCounter _diskActivityCounter;
    private static readonly object    _diskCounterLock = new object();

    private static void EnsureDiskCounters()
    {
        lock (_diskCounterLock)
        {
            if (_diskReadCounter != null) return;
            try
            {
                _diskReadCounter     = new PerformanceCounter("PhysicalDisk", "Disk Read Bytes/sec",  "_Total", true);
                _diskWriteCounter    = new PerformanceCounter("PhysicalDisk", "Disk Write Bytes/sec", "_Total", true);
                _diskActivityCounter = new PerformanceCounter("PhysicalDisk", "% Disk Time",          "_Total", true);
                // Primera lectura siempre devuelve 0 — descartarla
                _diskReadCounter.NextValue();
                _diskWriteCounter.NextValue();
                _diskActivityCounter.NextValue();
            }
            catch
            {
                _diskReadCounter = _diskWriteCounter = _diskActivityCounter = null;
            }
        }
    }

    // ── CPU ───────────────────────────────────────────────────────────────
    public static CpuSnapshot GetCpuSnapshot()
    {
        var snap = new CpuSnapshot { Timestamp = DateTime.UtcNow };
        try
        {
            using (var searcher = new ManagementObjectSearcher(
                "SELECT Name, NumberOfCores, NumberOfLogicalProcessors, LoadPercentage, CurrentClockSpeed, MaxClockSpeed FROM Win32_Processor"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    snap.Name               = SafeStr(obj, "Name").Trim();
                    snap.Cores              = SafeInt(obj, "NumberOfCores");
                    snap.LogicalProcessors  = SafeInt(obj, "NumberOfLogicalProcessors");
                    snap.LoadPercent        = SafeDouble(obj, "LoadPercentage");
                    snap.ClockMhz           = SafeDouble(obj, "CurrentClockSpeed");
                    snap.MaxClockMhz        = SafeDouble(obj, "MaxClockSpeed");
                    snap.TemperatureCelsius = -1; // WMI básico no expone temperatura de CPU
                    break; // primer procesador
                }
            }

            // Cargas por core via Win32_PerfFormattedData_PerfOS_Processor
            var coreLoads = new List<double>();
            try
            {
                using (var ps = new ManagementObjectSearcher(
                    "SELECT Name, PercentProcessorTime FROM Win32_PerfFormattedData_PerfOS_Processor WHERE Name != '_Total'"))
                {
                    var rows = new SortedDictionary<int, double>();
                    foreach (ManagementObject obj in ps.Get())
                    {
                        string cname = SafeStr(obj, "Name");
                        int    idx   = 0;
                        int.TryParse(cname, out idx);
                        rows[idx] = SafeDouble(obj, "PercentProcessorTime");
                    }
                    foreach (var kv in rows)
                        coreLoads.Add(kv.Value);
                }
            }
            catch { /* si falla, CoreLoads queda vacío */ }

            snap.CoreLoads = coreLoads.ToArray();
        }
        catch { }
        return snap;
    }

    // ── RAM ───────────────────────────────────────────────────────────────
    public static RamSnapshot GetRamSnapshot()
    {
        var snap = new RamSnapshot { Timestamp = DateTime.UtcNow };
        try
        {
            using (var searcher = new ManagementObjectSearcher(
                "SELECT TotalVisibleMemorySize, FreePhysicalMemory, TotalVirtualMemorySize, FreeVirtualMemory FROM Win32_OperatingSystem"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    long totalKB = SafeLong(obj, "TotalVisibleMemorySize");
                    long freeKB  = SafeLong(obj, "FreePhysicalMemory");
                    long pgTotKB = SafeLong(obj, "TotalVirtualMemorySize");
                    long pgFreeKB= SafeLong(obj, "FreeVirtualMemory");

                    snap.TotalBytes           = totalKB * 1024L;
                    snap.FreeBytes            = freeKB  * 1024L;
                    snap.UsedBytes            = snap.TotalBytes - snap.FreeBytes;
                    snap.UsedPercent          = snap.TotalBytes > 0
                        ? Math.Round(snap.UsedBytes * 100.0 / snap.TotalBytes, 1) : 0;
                    snap.PageFileTotalBytes   = pgTotKB  * 1024L;
                    snap.PageFileUsedBytes    = (pgTotKB - pgFreeKB) * 1024L;
                    snap.PageFileUsedPercent  = pgTotKB > 0
                        ? Math.Round(snap.PageFileUsedBytes * 100.0 / snap.PageFileTotalBytes, 1) : 0;
                    break;
                }
            }

            // Módulos físicos
            using (var mods = new ManagementObjectSearcher(
                "SELECT DeviceLocator, Capacity, SMBIOSMemoryType, Speed, Manufacturer FROM Win32_PhysicalMemory"))
            {
                foreach (ManagementObject obj in mods.Get())
                {
                    int typeCode = SafeInt(obj, "SMBIOSMemoryType");
                    string ramType = "DDR";
                    switch (typeCode)
                    {
                        case 21: ramType = "DDR2"; break;
                        case 24: ramType = "DDR3"; break;
                        case 26: ramType = "DDR4"; break;
                        case 34: ramType = "DDR5"; break;
                    }
                    snap.Modules.Add(new RamModuleInfo
                    {
                        Slot          = SafeStr(obj, "DeviceLocator"),
                        CapacityBytes = SafeLong(obj, "Capacity"),
                        Type          = ramType,
                        SpeedMhz      = SafeInt(obj, "Speed"),
                        Manufacturer  = SafeStr(obj, "Manufacturer")
                    });
                }
            }
        }
        catch { }
        return snap;
    }

    // ── Disco ─────────────────────────────────────────────────────────────
    public static DiskSnapshot GetDiskSnapshot()
    {
        var snap = new DiskSnapshot { Timestamp = DateTime.UtcNow };

        // Volúmenes lógicos vía WMI
        try
        {
            using (var searcher = new ManagementObjectSearcher(
                "SELECT DeviceID, VolumeName, FileSystem, Size, FreeSpace FROM Win32_LogicalDisk WHERE DriveType=3"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    long total = SafeLong(obj, "Size");
                    long free  = SafeLong(obj, "FreeSpace");
                    snap.Volumes.Add(new DiskVolumeInfo
                    {
                        DeviceId    = SafeStr(obj, "DeviceID"),
                        Label       = SafeStr(obj, "VolumeName"),
                        FileSystem  = SafeStr(obj, "FileSystem"),
                        TotalBytes  = total,
                        FreeBytes   = free,
                        UsedPercent = total > 0 ? Math.Round((total - free) * 100.0 / total, 1) : 0
                    });
                }
            }
        }
        catch { }

        // Discos físicos vía Win32_DiskDrive (SMART requiere Storage module,
        // aquí usamos WMI puro para compatibilidad PS 5.1 sin módulos extra)
        try
        {
            using (var searcher = new ManagementObjectSearcher(
                "SELECT Model, MediaType, InterfaceType, Size, Status FROM Win32_DiskDrive"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    string mediaRaw = SafeStr(obj, "MediaType").ToLower();
                    string media    = mediaRaw.Contains("solid") ? "SSD" :
                                     mediaRaw.Contains("fixed") ? "HDD" : mediaRaw;
                    snap.Drives.Add(new DiskDriveInfo
                    {
                        FriendlyName         = SafeStr(obj, "Model"),
                        MediaType            = media,
                        BusType              = SafeStr(obj, "InterfaceType"),
                        SizeBytes            = SafeLong(obj, "Size"),
                        HealthStatus         = SafeStr(obj, "Status"),
                        PowerOnHours         = -1,   // requiere Storage module
                        TemperatureCelsius   = -1,   // requiere Storage module
                        ReadErrorsTotal      = 0,
                        WearPercent          = -1
                    });
                }
            }
        }
        catch { }

        // Contadores de rendimiento
        try
        {
            EnsureDiskCounters();
            if (_diskReadCounter != null)
            {
                snap.ReadBytesPerSec  = Math.Max(0, _diskReadCounter.NextValue());
                snap.WriteBytesPerSec = Math.Max(0, _diskWriteCounter.NextValue());
                snap.ActivityPercent  = Math.Min(100, Math.Max(0, _diskActivityCounter.NextValue()));
            }
        }
        catch { }

        return snap;
    }

    // ── Red ───────────────────────────────────────────────────────────────
    public static NetworkSnapshot GetNetworkSnapshot()
    {
        var snap = new NetworkSnapshot { Timestamp = DateTime.UtcNow };
        try
        {
            // Tabla de velocidades WMI rx/tx por nombre de interfaz
            var wmiRates = new Dictionary<string, long[]>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (var perf = new ManagementObjectSearcher(
                    "SELECT Name, BytesReceivedPersec, BytesSentPersec FROM Win32_PerfFormattedData_Tcpip_NetworkInterface"))
                {
                    foreach (ManagementObject obj in perf.Get())
                    {
                        string nm = SafeStr(obj, "Name");
                        wmiRates[nm] = new long[]
                        {
                            SafeLong(obj, "BytesReceivedPersec"),
                            SafeLong(obj, "BytesSentPersec")
                        };
                    }
                }
            }
            catch { }

            // Adaptadores via .NET NetworkInterface (sin dependencia de cmdlets)
            var ifaces = NetworkInterface.GetAllNetworkInterfaces();
            foreach (var iface in ifaces)
            {
                // Saltar loopback y tunnel
                if (iface.NetworkInterfaceType == NetworkInterfaceType.Loopback ||
                    iface.NetworkInterfaceType == NetworkInterfaceType.Tunnel)
                    continue;

                var stats = iface.GetIPStatistics();
                var props = iface.GetIPProperties();

                string ip  = "";
                string gw  = "";
                foreach (var ua in props.UnicastAddresses)
                {
                    if (ua.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    { ip = ua.Address.ToString(); break; }
                }
                foreach (var g in props.GatewayAddresses)
                { gw = g.Address.ToString(); break; }

                string mac = BitConverter.ToString(iface.GetPhysicalAddress().GetAddressBytes())
                                         .Replace('-', ':');

                // Tipo
                string type = "Ethernet";
                string desc = iface.Description.ToLower();
                if (desc.Contains("wi-fi") || desc.Contains("wireless") || desc.Contains("wlan") ||
                    iface.NetworkInterfaceType == NetworkInterfaceType.Wireless80211)
                    type = "WiFi";
                else if (desc.Contains("hyper-v") || desc.Contains("vmware") ||
                         desc.Contains("virtualbox") || desc.Contains("tap") ||
                         desc.Contains("tun") || desc.Contains("vpn") || desc.Contains("loopback"))
                    type = "Virtual";

                // Velocidades rx/tx del contador WMI — buscar por nombre normalizado
                double rxBps = 0, txBps = 0;
                string normName = iface.Name.ToLower();
                foreach (var kv in wmiRates)
                {
                    string kNorm = kv.Key.ToLower().Replace("_", " ");
                    if (kNorm.Contains(normName) || normName.Contains(kNorm.Substring(0, Math.Min(10, kNorm.Length))))
                    {
                        rxBps = kv.Value[0];
                        txBps = kv.Value[1];
                        break;
                    }
                }

                snap.Adapters.Add(new NetworkAdapterInfo
                {
                    Name          = iface.Name,
                    Description   = iface.Description,
                    Type          = type,
                    MacAddress    = mac,
                    IpAddress     = ip,
                    Gateway       = gw,
                    IsUp          = iface.OperationalStatus == OperationalStatus.Up,
                    SpeedBps      = iface.Speed,
                    RxBytesPerSec = rxBps,
                    TxBytesPerSec = txBps,
                    TotalRxBytes  = stats.BytesReceived,
                    TotalTxBytes  = stats.BytesSent
                });
            }
        }
        catch { }
        return snap;
    }

    // ── GPU ───────────────────────────────────────────────────────────────
    public static GpuSnapshot GetGpuSnapshot()
    {
        var snap = new GpuSnapshot { Timestamp = DateTime.UtcNow };
        try
        {
            using (var searcher = new ManagementObjectSearcher(
                "SELECT Name, DriverVersion, AdapterRAM, VideoModeDescription, Availability FROM Win32_VideoController"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    int avail = SafeInt(obj, "Availability");
                    // Availability: 3=Running/Full power, 8=Offline, etc.
                    string status = avail == 3 ? "Active" :
                                   avail == 8 ? "Offline" : "Unknown";
                    snap.Gpus.Add(new GpuInfo
                    {
                        Name               = SafeStr(obj, "Name"),
                        DriverVersion      = SafeStr(obj, "DriverVersion"),
                        AdapterRamBytes    = SafeLong(obj, "AdapterRAM"),
                        VideoModeDesc      = SafeStr(obj, "VideoModeDescription"),
                        Status             = status,
                        TemperatureCelsius = -1  // WMI básico no lo expone; requiere vendor API
                    });
                }
            }
        }
        catch { }
        return snap;
    }

    // ── Puertos abiertos ──────────────────────────────────────────────────
    public static PortSnapshot GetPortSnapshot()
    {
        var snap = new PortSnapshot { Timestamp = DateTime.UtcNow };
        try
        {
            // Construir tabla PID → nombre de proceso una sola vez
            var pidNames = new Dictionary<int, string>();
            try
            {
                foreach (var proc in Process.GetProcesses())
                {
                    try { pidNames[proc.Id] = proc.ProcessName; } catch { }
                }
            }
            catch { }

            var ipProps = IPGlobalProperties.GetIPGlobalProperties();

            // TCP activo (Established, etc.)
            try
            {
                foreach (var conn in ipProps.GetActiveTcpConnections())
                {
                    snap.TcpPorts.Add(new OpenPortInfo
                    {
                        LocalPort     = conn.LocalEndPoint.Port,
                        LocalAddress  = conn.LocalEndPoint.Address.ToString(),
                        RemotePort    = conn.RemoteEndPoint.Port,
                        RemoteAddress = conn.RemoteEndPoint.Address.ToString(),
                        State         = conn.State.ToString(),
                        Pid           = 0,       // GetActiveTcpConnections no expone PID en .NET
                        ProcessName   = ""
                    });
                }
            }
            catch { }

            // TCP listeners (Listen)
            try
            {
                foreach (var ep in ipProps.GetActiveTcpListeners())
                {
                    snap.TcpPorts.Add(new OpenPortInfo
                    {
                        LocalPort    = ep.Port,
                        LocalAddress = ep.Address.ToString(),
                        RemotePort   = 0,
                        RemoteAddress= "",
                        State        = "Listen",
                        Pid          = 0,
                        ProcessName  = ""
                    });
                }
            }
            catch { }

            // UDP listeners
            try
            {
                foreach (var ep in ipProps.GetActiveUdpListeners())
                {
                    snap.UdpPorts.Add(new OpenPortInfo
                    {
                        LocalPort    = ep.Port,
                        LocalAddress = ep.Address.ToString(),
                        RemotePort   = 0,
                        RemoteAddress= "",
                        State        = "Listen",
                        Pid          = 0,
                        ProcessName  = ""
                    });
                }
            }
            catch { }

            // Enriquecer con PID/proceso vía WMI (MSFT_NetTCPConnection si disponible)
            // Esto es opcional y puede fallar en entornos restringidos — no bloquea
            try
            {
                using (var wmiTcp = new ManagementObjectSearcher(
                    @"root\StandardCimv2",
                    "SELECT LocalPort, OwningProcess FROM MSFT_NetTCPConnection"))
                {
                    var portPid = new Dictionary<int, int>();
                    foreach (ManagementObject obj in wmiTcp.Get())
                    {
                        int lp  = SafeInt(obj, "LocalPort");
                        int pid = SafeInt(obj, "OwningProcess");
                        if (lp > 0 && pid > 0) portPid[lp] = pid;
                    }
                    // Aplicar PIDs a los entries TCP ya creados
                    foreach (var p in snap.TcpPorts)
                    {
                        int pid;
                        if (portPid.TryGetValue(p.LocalPort, out pid))
                        {
                            p.Pid = pid;
                            string pname;
                            if (pidNames.TryGetValue(pid, out pname))
                                p.ProcessName = pname;
                        }
                    }
                }
            }
            catch { /* namespace root\StandardCimv2 puede no estar disponible */ }
        }
        catch { }
        return snap;
    }

    // ── Snapshot completo ─────────────────────────────────────────────────
    /// <summary>
    /// Recopila todos los módulos en una sola llamada.
    /// Ideal para el agente futuro: serializar SystemSnapshot y enviarlo.
    /// En modo standalone el PS llama los métodos individuales
    /// para actualizar solo la pestaña visible.
    /// </summary>
    public static SystemSnapshot GetFullSnapshot()
    {
        string osCaption = "";
        string osVersion = "";
        string osBuild   = "";
        DateTime bootTime = DateTime.MinValue;
        try
        {
            using (var os = new ManagementObjectSearcher(
                "SELECT Caption, Version, BuildNumber, LastBootUpTime FROM Win32_OperatingSystem"))
            {
                foreach (ManagementObject obj in os.Get())
                {
                    osCaption = SafeStr(obj, "Caption");
                    osVersion = SafeStr(obj, "Version");
                    osBuild   = SafeStr(obj, "BuildNumber");
                    string bootStr = SafeStr(obj, "LastBootUpTime");
                    if (!string.IsNullOrEmpty(bootStr))
                    {
                        try { bootTime = ManagementDateTimeConverter.ToDateTime(bootStr); }
                        catch { }
                    }
                    break;
                }
            }
        }
        catch { }

        return new SystemSnapshot
        {
            MachineName = Environment.MachineName,
            OsCaption   = osCaption,
            OsVersion   = osVersion,
            OsBuild     = osBuild,
            BootTime    = bootTime,
            Timestamp   = DateTime.UtcNow,
            Cpu         = GetCpuSnapshot(),
            Ram         = GetRamSnapshot(),
            Disk        = GetDiskSnapshot(),
            Network     = GetNetworkSnapshot(),
            Gpu         = GetGpuSnapshot(),
            Ports       = GetPortSnapshot()
        };
    }

    // ── Helpers WMI internos ──────────────────────────────────────────────
    private static string SafeStr(ManagementObject obj, string prop)
    {
        try { var v = obj[prop]; return v != null ? v.ToString() : ""; }
        catch { return ""; }
    }
    private static int SafeInt(ManagementObject obj, string prop)
    {
        try { var v = obj[prop]; if (v == null) return 0; int r; int.TryParse(v.ToString(), out r); return r; }
        catch { return 0; }
    }
    private static long SafeLong(ManagementObject obj, string prop)
    {
        try { var v = obj[prop]; if (v == null) return 0; long r; long.TryParse(v.ToString(), out r); return r; }
        catch { return 0; }
    }
    private static double SafeDouble(ManagementObject obj, string prop)
    {
        try { var v = obj[prop]; if (v == null) return 0; double r; double.TryParse(v.ToString(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out r); return r; }
        catch { return 0; }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN 5 — NUEVO: Agent hooks (standalone seguro, activable en el futuro)
// ─────────────────────────────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════════
// AgentThresholds — umbrales configurables para el modo push
// Cuando un valor supera el umbral, el agente emite un evento.
// En modo standalone estos valores existen pero nadie los consume.
// ═══════════════════════════════════════════════════════════════════════════════
public class AgentThresholds
{
    public double CpuLoadPercent      { get; set; }
    public double RamUsedPercent      { get; set; }
    public double DiskActivityPercent { get; set; }
    public double DiskUsedPercent     { get; set; }
    public int    DiskTempCelsius     { get; set; }
    public int    SnapshotIntervalSec { get; set; }

    // Constructor: inicializadores explícitos para compatibilidad con C# 5 / .NET 4.x
    public AgentThresholds()
    {
        CpuLoadPercent      = 85.0;
        RamUsedPercent      = 90.0;
        DiskActivityPercent = 95.0;
        DiskUsedPercent     = 90.0;
        DiskTempCelsius     = 55;
        SnapshotIntervalSec = 30;   // para modo pull
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IAgentTransport — interfaz que el agente futuro implementará
// En modo standalone no se instancia ninguna implementación.
// ═══════════════════════════════════════════════════════════════════════════════
public interface IAgentTransport
{
    /// <summary>Envía un snapshot completo al servidor (modo pull).</summary>
    void SendSnapshot(SystemSnapshot snapshot);

    /// <summary>Envía un evento de umbral superado (modo push).</summary>
    void SendAlert(string metric, double value, double threshold, DateTime timestamp);

    /// <summary>True si el canal de comunicación está disponible.</summary>
    bool IsConnected { get; }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AgentBus — bus de eventos que conecta el DAL con el transporte
// En modo standalone IsAgentEnabled = false y no hace nada.
// El agente futuro solo hace:
//   [AgentBus]::Transport = new MiTransporte(url, apiKey)
//   [AgentBus]::IsAgentEnabled = $true
// ═══════════════════════════════════════════════════════════════════════════════
public static class AgentBus
{
    public static bool            IsAgentEnabled { get; set; }
    public static IAgentTransport Transport      { get; set; }
    public static AgentThresholds Thresholds     { get; set; }

    // Constructor estático: compatibilidad con C# 5 / .NET 4.x
    static AgentBus()
    {
        IsAgentEnabled = false;
        Transport      = null;
        Thresholds     = new AgentThresholds();
    }

    /// <summary>
    /// Evalúa un snapshot contra los umbrales y dispara alertas si aplica.
    /// En standalone IsAgentEnabled=false → retorna inmediatamente, cero overhead.
    /// </summary>
    public static void EvaluateAndDispatch(SystemSnapshot snapshot)
    {
        if (!IsAgentEnabled || Transport == null || snapshot == null) return;

        var ts = snapshot.Timestamp;

        // CPU
        if (snapshot.Cpu != null && snapshot.Cpu.LoadPercent >= Thresholds.CpuLoadPercent)
            Transport.SendAlert("cpu.load", snapshot.Cpu.LoadPercent, Thresholds.CpuLoadPercent, ts);

        // RAM
        if (snapshot.Ram != null && snapshot.Ram.UsedPercent >= Thresholds.RamUsedPercent)
            Transport.SendAlert("ram.used", snapshot.Ram.UsedPercent, Thresholds.RamUsedPercent, ts);

        // Disco — actividad
        if (snapshot.Disk != null && snapshot.Disk.ActivityPercent >= Thresholds.DiskActivityPercent)
            Transport.SendAlert("disk.activity", snapshot.Disk.ActivityPercent, Thresholds.DiskActivityPercent, ts);

        // Disco — uso por volumen
        if (snapshot.Disk != null)
        {
            foreach (var vol in snapshot.Disk.Volumes)
            {
                if (vol.UsedPercent >= Thresholds.DiskUsedPercent)
                    Transport.SendAlert("disk.volume." + vol.DeviceId, vol.UsedPercent, Thresholds.DiskUsedPercent, ts);
            }
            // Temperatura de discos
            foreach (var drv in snapshot.Disk.Drives)
            {
                if (drv.TemperatureCelsius >= Thresholds.DiskTempCelsius)
                    Transport.SendAlert("disk.temp." + drv.FriendlyName, drv.TemperatureCelsius, Thresholds.DiskTempCelsius, ts);
            }
        }

        // Snapshot completo (modo pull)
        try { Transport.SendSnapshot(snapshot); } catch { }
    }
}
// =============================================================================
// SECCIÓN 6 — LogEngine
// Logger thread-safe con rotación diaria y mutex con nombre.
// Reemplaza el StreamWriter + Mutex inline de SysOpt.ps1 (línea ~819).
//
// Uso en PS:
//   [LogEngine]::Initialize($logDir)          # una vez al arrancar
//   [LogEngine]::Write("mensaje", "INFO")     # desde cualquier runspace
//   [LogEngine]::Header("SysOpt", "3.2.0")   # cabecera de sesión
//   [LogEngine]::Close()                      # en Add_Closed
// =============================================================================

public static class LogEngine
{
    // ── Estado interno ────────────────────────────────────────────────────────
    private static StreamWriter  _writer      = null;
    private static Mutex         _mutex       = null;
    private static string        _currentDate = null;
    private static string        _logDir      = null;
    private static readonly object _initLock  = new object();

    // ── Debug toggle ──────────────────────────────────────────────────────────
    /// <summary>
    /// Cuando es false (por defecto), los mensajes con nivel "DBG" se descartan.
    /// Activable desde Opciones → "Habilitar logs de depuración".
    /// </summary>
    public static bool DebugEnabled { get; set; }

    // ── Initialize ────────────────────────────────────────────────────────────
    /// <summary>
    /// Inicializa (o reinicializa por rotación diaria) el logger.
    /// Llama una vez al arrancar y siempre que cambie el día.
    /// Idempotente: si ya está inicializado para hoy, no hace nada.
    /// </summary>
    public static void Initialize(string logDir)
    {
        if (string.IsNullOrEmpty(logDir)) throw new ArgumentNullException("logDir");

        lock (_initLock)
        {
            string today = DateTime.Now.ToString("yyyy-MM-dd");

            // Ya inicializado para hoy
            if (_currentDate == today && _writer != null) return;

            _logDir = logDir;

            // Cerrar writer anterior si existe (rotación)
            CloseWriter();

            if (!Directory.Exists(logDir))
                Directory.CreateDirectory(logDir);

            string logFile = Path.Combine(logDir, "SysOpt_" + today + ".log");

            var fs     = File.Open(logFile, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
            _writer    = new StreamWriter(fs, System.Text.Encoding.UTF8);
            _writer.AutoFlush = true;
            _currentDate = today;

            // Mutex con nombre único por PID — permite que runspaces lo adquieran
            if (_mutex == null)
            {
                string mutexName = "SysOpt_LogMutex_" + System.Diagnostics.Process.GetCurrentProcess().Id;
                _mutex = new Mutex(false, mutexName);
            }
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────
    /// <summary>Escribe la cabecera de sesión al archivo de log.</summary>
    public static void Header(string appName, string version)
    {
        EnsureDay();
        string sep  = new string('═', 60);
        string line = string.Format(Loc.T("CoreSessionStarted", "  {0} v{1}  —  Sesión iniciada: {2}"),
            appName, version, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        string host = string.Format("  Usuario: {0}  |  Host: {1}",
            Environment.UserName, Environment.MachineName);

        WriteRaw("");
        WriteRaw(sep);
        WriteRaw(line);
        WriteRaw(host);
        WriteRaw(sep);
    }

    // ── Write ─────────────────────────────────────────────────────────────────
    /// <summary>
    /// Escribe una línea al log. Seguro desde cualquier runspace/hilo.
    /// level: "DBG" | "INFO" | "WARN" | "ERR" | "CRIT"  (cualquier otro valor se admite tal cual)
    /// </summary>
    public static void Write(string message, string level)
    {
        if (message == null) message = "";
        if (string.IsNullOrEmpty(level)) level = "INFO";

        // Nivel UI y líneas vacías en INFO no van al archivo
        if (level == "UI") return;
        if (level == "INFO" && message.Trim().Length == 0) return;

        // DBG solo se escribe si DebugEnabled está activo
        if (level == "DBG" && !DebugEnabled) return;

        EnsureDay();

        string line = string.Format("[{0}][{1}] {2}",
            DateTime.Now.ToString("HH:mm:ss"), level, message);

        bool acquired = false;
        try
        {
            if (_mutex != null) acquired = _mutex.WaitOne(200);
            if (_writer != null) _writer.WriteLine(line);
        }
        catch { }
        finally
        {
            if (acquired) { try { _mutex.ReleaseMutex(); } catch { } }
        }
    }

    // ── Close ─────────────────────────────────────────────────────────────────
    /// <summary>Cierra el writer y libera el mutex. Llama en Add_Closed.</summary>
    public static void Close()
    {
        lock (_initLock)
        {
            CloseWriter();
            if (_mutex != null)
            {
                try { _mutex.Dispose(); } catch { }
                _mutex = null;
            }
        }
    }

    // ── Helpers privados ──────────────────────────────────────────────────────
    private static void EnsureDay()
    {
        if (_logDir == null || _writer != null && _currentDate == DateTime.Now.ToString("yyyy-MM-dd"))
            return;
        Initialize(_logDir);   // rotación silenciosa
    }

    private static void CloseWriter()
    {
        if (_writer != null)
        {
            try { _writer.Flush();   } catch { }
            try { _writer.Close();   } catch { }
            try { _writer.Dispose(); } catch { }
            _writer = null;
        }
        _currentDate = null;
    }

    private static void WriteRaw(string line)
    {
        bool acquired = false;
        try
        {
            if (_mutex != null) acquired = _mutex.WaitOne(200);
            if (_writer != null) _writer.WriteLine(line);
        }
        catch { }
        finally
        {
            if (acquired) { try { _mutex.ReleaseMutex(); } catch { } }
        }
    }
}
// =============================================================================
// SECCIÓN 7 — SysOptFallbacks
// Lógica de arranque que antes vivía inline en SysOpt.ps1:
//   · AppMutex — instancia única de la aplicación
//   · DllLoader — carga y guarda de DLLs con guard-type
//   · RunspacePoolState — flag que el PS consulta para saber si el pool está vivo
//
// Uso en PS (reemplaza el bloque inline de ~línea 305-415):
//   [SysOptFallbacks]::InitMutex("Global\OptimizadorSistemaGUI_v5")
//   if (-not [SysOptFallbacks]::AcquireMutex()) { exit }
//   [SysOptFallbacks]::RunspacePoolAvailable = $true   # lo escribe Initialize-RunspacePool
//   [SysOptFallbacks]::ReleaseMutex()                  # en Add_Closed
// =============================================================================
public static class SysOptFallbacks
{
    // ── AppMutex ─────────────────────────────────────────────────────────────
    private static Mutex  _appMutex     = null;
    private static bool   _mutexOwned   = false;
    private static readonly object _mLock = new object();

    /// <summary>
    /// Crea el mutex de instancia única.
    /// Llama UNA SOLA VEZ al arrancar, antes de mostrar ninguna ventana.
    /// </summary>
    public static void InitMutex(string mutexName)
    {
        if (string.IsNullOrEmpty(mutexName)) throw new ArgumentNullException("mutexName");
        lock (_mLock)
        {
            if (_appMutex != null) return;
            _appMutex = new Mutex(false, mutexName);
        }
    }

    /// <summary>
    /// Intenta adquirir el mutex (timeout 0 ms).
    /// Devuelve true si esta instancia es la primera; false si ya hay otra corriendo.
    /// Maneja AbandonedMutexException (proceso anterior murió sin liberar).
    /// </summary>
    public static bool AcquireMutex()
    {
        lock (_mLock)
        {
            if (_appMutex == null) return true; // sin mutex → siempre permitir
            try
            {
                _mutexOwned = _appMutex.WaitOne(0);
                return _mutexOwned;
            }
            catch (AbandonedMutexException)
            {
                // El proceso anterior murió sin liberar — el mutex nos pertenece
                _mutexOwned = true;
                return true;
            }
            catch
            {
                return true; // ante duda, permitir arranque
            }
        }
    }

    /// <summary>Libera el mutex al cerrar la aplicación.</summary>
    public static void ReleaseMutex()
    {
        lock (_mLock)
        {
            if (_appMutex == null || !_mutexOwned) return;
            try   { _appMutex.ReleaseMutex(); _mutexOwned = false; }
            catch { }
        }
    }

    /// <summary>Libera y descarta el mutex (llamar en Add_Closed).</summary>
    public static void DisposeMutex()
    {
        lock (_mLock)
        {
            ReleaseMutex();
            try   { if (_appMutex != null) _appMutex.Dispose(); } catch { }
            _appMutex = null;
        }
    }

    // ── RunspacePool state ────────────────────────────────────────────────────
    /// <summary>
    /// True cuando Initialize-RunspacePool consiguió abrir el pool.
    /// False cuando falló y el PS usa runspaces individuales como fallback.
    /// PowerShell lo escribe; New-TrackedPS lo lee para decidir el modo.
    /// </summary>
    public static volatile bool RunspacePoolAvailable = false;

    // ── DllLoader registry ────────────────────────────────────────────────────
    // Registro de ensamblados ya cargados en esta sesión, evitando
    // llamadas redundantes a Add-Type que lanzan errores por duplicado.
    private static readonly System.Collections.Generic.HashSet<string> _loaded
        = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
    private static readonly object _loadLock = new object();

    /// <summary>
    /// Devuelve true si el guardType ya fue registrado como cargado.
    /// El PS llama a RegisterLoaded() justo después de Add-Type exitoso.
    /// </summary>
    public static bool IsLoaded(string guardType)
    {
        if (string.IsNullOrEmpty(guardType)) return false;
        lock (_loadLock) { return _loaded.Contains(guardType); }
    }

    /// <summary>Marca un guardType como cargado en esta sesión.</summary>
    public static void RegisterLoaded(string guardType)
    {
        if (string.IsNullOrEmpty(guardType)) return;
        lock (_loadLock) { _loaded.Add(guardType); }
    }

    /// <summary>
    /// Intenta cargar un ensamblado externo vía reflexión.
    /// Devuelve null si ya estaba cargado o si la carga falla.
    /// En caso de fallo: si hard=true lanza excepción; si false retorna null.
    /// El PS ya no necesita el bloque try/catch de Load-SysOptDll.
    /// </summary>
    public static System.Reflection.Assembly LoadDll(
        string dllPath, string guardType, bool hard)
    {
        if (IsLoaded(guardType)) return null;

        if (!File.Exists(dllPath))
        {
            string msg = "SysOpt DLL no encontrada: " + dllPath + " (guard=" + guardType + ")";
            if (hard) throw new FileNotFoundException(msg, dllPath);
            return null;
        }

        try
        {
            var asm = System.Reflection.Assembly.LoadFrom(dllPath);
            RegisterLoaded(guardType);
            return asm;
        }
        catch (Exception ex)
        {
            string msg = "SysOpt: no se pudo cargar " + dllPath + " — " + ex.Message;
            if (hard) throw new InvalidOperationException(msg, ex);
            return null;
        }
    }
}
// ═══════════════════════════════════════════════════════════════════════════════
// Formatter — Formatting utilities (replaces PS1 Format-Bytes, Format-Rate, etc.)
// ═══════════════════════════════════════════════════════════════════════════════
public static class Formatter
{
    public static string FormatBytes(long bytes)
    {
        if (bytes >= 1073741824L) return string.Format("{0:N1} GB", bytes / 1073741824.0);
        if (bytes >= 1048576L)    return string.Format("{0:N0} MB", bytes / 1048576.0);
        if (bytes >= 1024L)       return string.Format("{0:N0} KB", bytes / 1024.0);
        return bytes + " B";
    }

    public static string FormatRate(double bps)
    {
        if (bps >= 1048576.0) return string.Format("{0:N1} MB/s", bps / 1048576.0);
        if (bps >= 1024.0)    return string.Format("{0:N0} KB/s", bps / 1024.0);
        if (bps > 0)          return string.Format("{0:N0} B/s", bps);
        return "0 B/s";
    }

    public static string FormatLinkSpeed(ulong bps)
    {
        if (bps >= 1000000000UL) return Math.Round(bps / 1e9, 0) + " Gbps";
        if (bps >= 1000000UL)    return Math.Round(bps / 1e6, 0) + " Mbps";
        if (bps > 0)             return bps + " bps";
        return "\u2014";
    }

    public static ulong ParseLinkBps(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return 0;
        ulong n;
        if (ulong.TryParse(raw.Trim(), out n)) return n;
        var m = System.Text.RegularExpressions.Regex.Match(raw, @"([\d\.]+)\s*(G|M|K)?bps");
        if (m.Success)
        {
            double v = double.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture);
            string u = m.Groups[2].Value;
            double mul = u == "G" ? 1e9 : u == "M" ? 1e6 : u == "K" ? 1e3 : 1;
            return (ulong)(v * mul);
        }
        return 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CleanupResult — Result container for cleanup operations
// ═══════════════════════════════════════════════════════════════════════════════
public class CleanupResult
{
    public double FreedMB        { get; set; }
    public int    FilesProcessed { get; set; }
    public int    Errors         { get; set; }
    public bool   Success        { get; set; }
    public string Summary        { get; set; }
    public System.Collections.Generic.List<string> Messages { get; set; }

    public CleanupResult()
    {
        Messages = new System.Collections.Generic.List<string>();
        Success  = true;
        Summary  = "";
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CleanupEngine — Core cleanup operations (replaces PS1 optimization blocks)
// ═══════════════════════════════════════════════════════════════════════════════
public static class CleanupEngine
{
    /// <summary>
    /// Recursively scan and optionally delete files in given paths.
    /// Replaces PS1 Invoke-CleanTempPaths (~60 lines).
    /// </summary>
    public static CleanupResult CleanPaths(string[] paths, bool dryRun)
    {
        var result = new CleanupResult();
        int pathIdx = 0;
        foreach (string path in paths)
        {
            pathIdx++;
            string tag = "[" + pathIdx + "/" + paths.Length + "]";
            if (!System.IO.Directory.Exists(path))
            {
                result.Messages.Add("  " + tag + " Ruta no encontrada: " + path);
                continue;
            }
            result.Messages.Add("  " + tag + " Analizando: " + path);
            try
            {
                long beforeSize = GetDirectorySize(path);
                double beforeMB = Math.Round(beforeSize / 1048576.0, 2);
                result.Messages.Add("    Tama\u00f1o: " + beforeMB + " MB");

                if (!dryRun)
                {
                    int deleted = 0;
                    foreach (string file in SafeEnumerateFiles(path))
                    {
                        try { System.IO.File.Delete(file); deleted++; }
                        catch { result.Errors++; }
                    }
                    // Remove empty directories bottom-up
                    foreach (string dir in SafeEnumerateDirectories(path))
                    {
                        try { System.IO.Directory.Delete(dir, true); } catch { }
                    }
                    long afterSize = GetDirectorySize(path);
                    double freed = Math.Round((beforeSize - afterSize) / 1048576.0, 2);
                    result.FreedMB += freed;
                    result.FilesProcessed += deleted;
                    result.Messages.Add("    \u2713 Eliminados: " + deleted + " archivos \u2014 " + freed + " MB liberados");
                }
                else
                {
                    result.FreedMB += beforeMB;
                    result.Messages.Add("    [DRY RUN] Se liberar\u00edan ~" + beforeMB + " MB");
                }
            }
            catch (Exception ex)
            {
                result.Errors++;
                result.Messages.Add("    ! Error: " + ex.Message);
            }
        }
        return result;
    }

    /// <summary>
    /// Clean Recycle Bin on all drives.
    /// Replaces PS1 RecycleBin block (~43 lines).
    /// </summary>
    public static CleanupResult EmptyRecycleBin(bool dryRun)
    {
        var result = new CleanupResult();
        try
        {
            double totalMB = 0;
            foreach (var drive in System.IO.DriveInfo.GetDrives())
            {
                if (drive.DriveType != System.IO.DriveType.Fixed) continue;
                string rbPath = System.IO.Path.Combine(drive.RootDirectory.FullName, "$Recycle.Bin");
                if (System.IO.Directory.Exists(rbPath))
                {
                    long sz = GetDirectorySize(rbPath);
                    totalMB += sz / 1048576.0;
                }
            }
            totalMB = Math.Round(totalMB, 2);
            result.FreedMB = totalMB;
            result.Messages.Add("  Contenido total en papelera: " + totalMB + " MB");

            if (dryRun)
            {
                result.Messages.Add("  [DRY RUN] Se liberar\u00edan ~" + totalMB + " MB");
            }
            else
            {
                foreach (var drive in System.IO.DriveInfo.GetDrives())
                {
                    if (drive.DriveType != System.IO.DriveType.Fixed) continue;
                    string rbPath = System.IO.Path.Combine(drive.RootDirectory.FullName, "$Recycle.Bin");
                    if (System.IO.Directory.Exists(rbPath))
                    {
                        foreach (string item in SafeEnumerateEntries(rbPath))
                        {
                            try
                            {
                                if (System.IO.File.Exists(item))
                                    System.IO.File.Delete(item);
                                else if (System.IO.Directory.Exists(item))
                                    System.IO.Directory.Delete(item, true);
                            }
                            catch { result.Errors++; }
                        }
                    }
                }
                result.Messages.Add("  \u2713 Papelera vaciada para todas las unidades \u2014 " + totalMB + " MB liberados");
            }
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Messages.Add("  \u274c Error: " + ex.Message);
        }
        return result;
    }

    /// <summary>
    /// Clean browser caches (Chrome, Edge, Brave, Opera, Opera GX, Firefox).
    /// Replaces PS1 BrowserCache block (~105 lines).
    /// </summary>
    public static CleanupResult CleanBrowserCaches(bool dryRun)
    {
        var result = new CleanupResult();
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string appData      = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

        var browsers = new System.Collections.Generic.Dictionary<string, string[]>
        {
            { "Chrome", new[] {
                System.IO.Path.Combine(localAppData, @"Google\Chrome\User Data\Default\Cache"),
                System.IO.Path.Combine(localAppData, @"Google\Chrome\User Data\Default\Cache2"),
                System.IO.Path.Combine(localAppData, @"Google\Chrome\User Data\Default\Code Cache"),
                System.IO.Path.Combine(localAppData, @"Google\Chrome\User Data\Default\GPUCache") }},
            { "Edge", new[] {
                System.IO.Path.Combine(localAppData, @"Microsoft\Edge\User Data\Default\Cache"),
                System.IO.Path.Combine(localAppData, @"Microsoft\Edge\User Data\Default\Cache2"),
                System.IO.Path.Combine(localAppData, @"Microsoft\Edge\User Data\Default\Code Cache"),
                System.IO.Path.Combine(localAppData, @"Microsoft\Edge\User Data\Default\GPUCache") }},
            { "Brave", new[] {
                System.IO.Path.Combine(localAppData, @"BraveSoftware\Brave-Browser\User Data\Default\Cache"),
                System.IO.Path.Combine(localAppData, @"BraveSoftware\Brave-Browser\User Data\Default\Cache2"),
                System.IO.Path.Combine(localAppData, @"BraveSoftware\Brave-Browser\User Data\Default\Code Cache"),
                System.IO.Path.Combine(localAppData, @"BraveSoftware\Brave-Browser\User Data\Default\GPUCache") }},
            { "Opera", new[] {
                System.IO.Path.Combine(appData, @"Opera Software\Opera Stable\Cache"),
                System.IO.Path.Combine(appData, @"Opera Software\Opera Stable\Cache2"),
                System.IO.Path.Combine(appData, @"Opera Software\Opera Stable\Code Cache"),
                System.IO.Path.Combine(appData, @"Opera Software\Opera Stable\GPUCache") }},
            { "Opera GX", new[] {
                System.IO.Path.Combine(appData, @"Opera Software\Opera GX Stable\Cache"),
                System.IO.Path.Combine(appData, @"Opera Software\Opera GX Stable\Cache2"),
                System.IO.Path.Combine(appData, @"Opera Software\Opera GX Stable\Code Cache"),
                System.IO.Path.Combine(appData, @"Opera Software\Opera GX Stable\GPUCache") }},
        };

        int bIdx = 0;
        int bCount = browsers.Count + 1; // +1 for Firefox

        foreach (var kv in browsers)
        {
            bIdx++;
            result.Messages.Add("  [" + bIdx + "/" + bCount + "] " + kv.Key + "...");
            double totalCleared = 0;
            bool cleared = false;

            foreach (string path in kv.Value)
            {
                if (System.IO.Directory.Exists(path))
                {
                    long sz = GetDirectorySize(path);
                    totalCleared += sz / 1048576.0;
                    if (!dryRun)
                    {
                        foreach (string item in SafeEnumerateEntries(path))
                        {
                            try
                            {
                                if (System.IO.File.Exists(item))
                                    System.IO.File.Delete(item);
                                else if (System.IO.Directory.Exists(item))
                                    System.IO.Directory.Delete(item, true);
                            }
                            catch { }
                        }
                    }
                    cleared = true;
                }
            }
            totalCleared = Math.Round(totalCleared, 2);
            result.FreedMB += totalCleared;
            if (cleared)
                result.Messages.Add("    " + (dryRun ? "[DRY RUN]" : "\u2713") + " " + kv.Key + " \u2014 " + totalCleared + " MB " + (dryRun ? "por liberar" : "liberados"));
            else
                result.Messages.Add("    \u2192 " + kv.Key + " no encontrado o sin cach\u00e9");
        }

        // Firefox — special handling (profiles)
        bIdx++;
        result.Messages.Add("  [" + bIdx + "/" + bCount + "] Firefox...");
        string ffProfilesPath = System.IO.Path.Combine(localAppData, @"Mozilla\Firefox\Profiles");
        double ffCleared = 0;
        bool ffFound = false;
        if (System.IO.Directory.Exists(ffProfilesPath))
        {
            foreach (string profileDir in System.IO.Directory.GetDirectories(ffProfilesPath))
            {
                foreach (string cacheSub in new[] { "cache", "cache2" })
                {
                    string cp = System.IO.Path.Combine(profileDir, cacheSub);
                    if (System.IO.Directory.Exists(cp))
                    {
                        long sz = GetDirectorySize(cp);
                        ffCleared += sz / 1048576.0;
                        if (!dryRun)
                        {
                            foreach (string item in SafeEnumerateEntries(cp))
                            {
                                try
                                {
                                    if (System.IO.File.Exists(item))
                                        System.IO.File.Delete(item);
                                    else if (System.IO.Directory.Exists(item))
                                        System.IO.Directory.Delete(item, true);
                                }
                                catch { }
                            }
                        }
                        ffFound = true;
                    }
                }
            }
        }
        ffCleared = Math.Round(ffCleared, 2);
        result.FreedMB += ffCleared;
        if (ffFound)
            result.Messages.Add("    " + (dryRun ? "[DRY RUN]" : "\u2713") + " Firefox \u2014 " + ffCleared + " MB " + (dryRun ? "por liberar" : "liberados"));
        else
            result.Messages.Add("    \u2192 Firefox no encontrado o sin cach\u00e9");

        result.Messages.Add("");
        result.Messages.Add("  \u2713 Limpieza de navegadores " + (dryRun ? "analizada" : "completada"));
        return result;
    }

    /// <summary>
    /// Clean orphaned registry uninstall keys.
    /// Replaces PS1 CleanRegistry block (~63 lines).
    /// </summary>
    public static CleanupResult CleanRegistryOrphans(bool dryRun)
    {
        var result = new CleanupResult();
        string[] regPaths = new[]
        {
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        };
        int orphaned = 0, deleted = 0;

        // HKLM paths
        foreach (string regPath in regPaths)
        {
            result.Messages.Add("  Analizando: HKLM\\" + regPath);
            try
            {
                using (var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(regPath))
                {
                    if (key == null) continue;
                    foreach (string subName in key.GetSubKeyNames())
                    {
                        try
                        {
                            using (var sub = key.OpenSubKey(subName))
                            {
                                if (sub == null) continue;
                                string installLoc = sub.GetValue("InstallLocation") as string;
                                string displayName = (sub.GetValue("DisplayName") as string) ?? subName;
                                if (!string.IsNullOrWhiteSpace(installLoc) && !System.IO.Directory.Exists(installLoc))
                                {
                                    orphaned++;
                                    result.Messages.Add("    \u2192 Hu\u00e9rfana: " + displayName);
                                    if (!dryRun)
                                    {
                                        try
                                        {
                                            using (var parent = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(regPath, true))
                                            {
                                                parent.DeleteSubKeyTree(subName);
                                                deleted++;
                                                result.Messages.Add("      \u2713 Eliminada");
                                            }
                                        }
                                        catch (Exception ex)
                                        {
                                            result.Messages.Add("      ! No se pudo eliminar: " + ex.Message);
                                        }
                                    }
                                    else
                                    {
                                        result.Messages.Add("      [DRY RUN] Se eliminar\u00eda");
                                    }
                                }
                            }
                        }
                        catch { }
                    }
                }
            }
            catch { }
        }

        // HKCU path
        string hkcuPath = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";
        result.Messages.Add("  Analizando: HKCU\\" + hkcuPath);
        try
        {
            using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(hkcuPath))
            {
                if (key != null)
                {
                    foreach (string subName in key.GetSubKeyNames())
                    {
                        try
                        {
                            using (var sub = key.OpenSubKey(subName))
                            {
                                if (sub == null) continue;
                                string installLoc = sub.GetValue("InstallLocation") as string;
                                string displayName = (sub.GetValue("DisplayName") as string) ?? subName;
                                if (!string.IsNullOrWhiteSpace(installLoc) && !System.IO.Directory.Exists(installLoc))
                                {
                                    orphaned++;
                                    result.Messages.Add("    \u2192 Hu\u00e9rfana: " + displayName);
                                    if (!dryRun)
                                    {
                                        try
                                        {
                                            using (var parent = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(hkcuPath, true))
                                            {
                                                parent.DeleteSubKeyTree(subName);
                                                deleted++;
                                                result.Messages.Add("      \u2713 Eliminada");
                                            }
                                        }
                                        catch (Exception ex)
                                        {
                                            result.Messages.Add("      ! No se pudo eliminar: " + ex.Message);
                                        }
                                    }
                                    else
                                    {
                                        result.Messages.Add("      [DRY RUN] Se eliminar\u00eda");
                                    }
                                }
                            }
                        }
                        catch { }
                    }
                }
            }
        }
        catch { }

        result.Messages.Add("");
        result.Messages.Add("  \u2713 Hu\u00e9rfanas encontradas: " + orphaned + " \u2014 Eliminadas: " + deleted);
        result.Summary = orphaned.ToString();
        result.FilesProcessed = orphaned;
        return result;
    }

    /// <summary>
    /// Clear Windows Event Logs (System, Application, Setup).
    /// Replaces PS1 EventLogs block (~45 lines).
    /// </summary>
    public static CleanupResult CleanEventLogs(string[] logNames, bool dryRun)
    {
        var result = new CleanupResult();
        int lIdx = 0;
        foreach (string logName in logNames)
        {
            lIdx++;
            string tag = "[" + lIdx + "/" + logNames.Length + "]";
            try
            {
                System.Diagnostics.Eventing.Reader.EventLogConfiguration config =
                    new System.Diagnostics.Eventing.Reader.EventLogConfiguration(logName);
                double sizeMB = Math.Round(config.LogFilePath != null ?
                    new System.IO.FileInfo(
                        Environment.ExpandEnvironmentVariables(
                            config.LogFilePath)).Length / 1048576.0 : 0, 2);
                result.FreedMB += sizeMB;

                result.Messages.Add("  " + tag + " " + logName + " \u2014 " + sizeMB + " MB");

                if (dryRun)
                {
                    result.Messages.Add("    [DRY RUN] Se limpiar\u00eda este log");
                }
                else
                {
                    var psi = new System.Diagnostics.ProcessStartInfo
                    {
                        FileName = "wevtutil.exe",
                        Arguments = "cl " + logName,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true
                    };
                    using (var proc = System.Diagnostics.Process.Start(psi))
                    {
                        proc.WaitForExit(30000);
                    }
                    result.Messages.Add("    \u2713 Log limpiado");
                }
            }
            catch (Exception ex)
            {
                result.Messages.Add("  " + tag + " " + logName + " \u2014 Error: " + ex.Message);
            }
        }
        result.Messages.Add("");
        result.Messages.Add("  \u2713 Event Logs " + (dryRun ? "analizados" : "limpiados"));
        result.Messages.Add("  NOTA: El log 'Security' NO fue modificado (requiere auditor\u00eda)");
        return result;
    }

    /// <summary>
    /// Flush DNS cache via ipconfig /flushdns.
    /// Replaces PS1 DNS block (~45 lines).
    /// </summary>
    public static CleanupResult FlushDns(bool dryRun)
    {
        var result = new CleanupResult();
        if (dryRun)
        {
            result.Messages.Add("  [DRY RUN] Se ejecutar\u00eda ipconfig /flushdns");
            return result;
        }
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/c chcp 65001 >nul 2>&1 & ipconfig /flushdns",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8
            };
            using (var proc = System.Diagnostics.Process.Start(psi))
            {
                string output = proc.StandardOutput.ReadToEnd();
                proc.WaitForExit(15000);
                foreach (string line in output.Split('\n'))
                {
                    string trimmed = line.Trim();
                    if (!string.IsNullOrEmpty(trimmed))
                        result.Messages.Add("  " + trimmed);
                }
            }
            result.Messages.Add("  \u2713 Cach\u00e9 DNS limpiada");
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Messages.Add("  Error: " + ex.Message);
        }
        return result;
    }

    /// <summary>
    /// Backup registry hives via reg.exe export.
    /// Replaces PS1 BackupRegistry block (~51 lines).
    /// </summary>
    public static CleanupResult BackupRegistry(string outputFolder, bool dryRun)
    {
        var result = new CleanupResult();
        var hives = new[] {
            new { Name = "HKEY_CURRENT_USER",           File = "HKCU_backup.reg" },
            new { Name = "HKEY_LOCAL_MACHINE\\SOFTWARE", File = "HKLM_SOFTWARE_backup.reg" }
        };

        if (dryRun)
        {
            result.Messages.Add("  [DRY RUN] Se crear\u00eda backup en: " + outputFolder);
            result.Messages.Add("  [DRY RUN] Exportar\u00eda: " + string.Join(", ", System.Linq.Enumerable.Select(hives, h => h.Name)));
            return result;
        }

        try
        {
            System.IO.Directory.CreateDirectory(outputFolder);
            result.Messages.Add("  Carpeta: " + outputFolder);

            int hi = 0;
            foreach (var hive in hives)
            {
                hi++;
                result.Messages.Add("  [" + hi + "/" + hives.Length + "] Exportando " + hive.Name + "...");
                string exportFile = System.IO.Path.Combine(outputFolder, hive.File);
                var psi = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = "/c reg export \"" + hive.Name + "\" \"" + exportFile + "\" /y",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (var proc = System.Diagnostics.Process.Start(psi))
                {
                    proc.WaitForExit(120000);
                }
                if (System.IO.File.Exists(exportFile))
                {
                    double sz = Math.Round(new System.IO.FileInfo(exportFile).Length / 1048576.0, 2);
                    result.Messages.Add("    \u2713 " + sz + " MB");
                }
                else
                {
                    result.Messages.Add("    ! No se pudo exportar");
                }
            }
            result.Messages.Add("");
            result.Messages.Add("  \u2713 Backup completado en: " + outputFolder);
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Messages.Add("  Error: " + ex.Message);
        }
        return result;
    }

    /// <summary>
    /// Run an external tool and capture output.
    /// Replaces inline Process.Start patterns for SFC, DISM, defrag, etc.
    /// </summary>
    public static CleanupResult RunExternalTool(string fileName, string arguments, int timeoutMs = 0)
    {
        var result = new CleanupResult();
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8
            };
            using (var proc = System.Diagnostics.Process.Start(psi))
            {
                string stdout = proc.StandardOutput.ReadToEnd();
                string stderr = proc.StandardError.ReadToEnd();
                if (timeoutMs > 0)
                    proc.WaitForExit(timeoutMs);
                else
                    proc.WaitForExit();

                foreach (string line in stdout.Split('\n'))
                {
                    string t = line.TrimEnd();
                    if (!string.IsNullOrEmpty(t))
                        result.Messages.Add("    " + t);
                }
                result.Summary = proc.ExitCode.ToString();
            }
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Messages.Add("  Error: " + ex.Message);
        }
        return result;
    }


    /// <summary>
    /// Run SFC /SCANNOW and interpret results.
    /// Replaces PS1 SFC block (~38 lines).
    /// </summary>
    public static CleanupResult RunSfc(bool dryRun)
    {
        var result = new CleanupResult();
        result.Messages.Add("    NOTA: puede tardar entre 10-30 minutos");

        if (dryRun)
        {
            result.Messages.Add("  [DRY RUN] Se ejecutar\u00eda: sfc.exe /scannow");
            return result;
        }

        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "sfc.exe",
                Arguments = "/scannow",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var proc = System.Diagnostics.Process.Start(psi))
            {
                proc.WaitForExit(); // SFC can take 30+ min

                // Read CBS.log for details
                string cbsLog = System.IO.Path.Combine(
                    Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows",
                    @"Logs\CBS\CBS.log");
                if (System.IO.File.Exists(cbsLog))
                {
                    result.Messages.Add("  \u00daltimas l\u00edneas CBS.log:");
                    try
                    {
                        var lines = System.IO.File.ReadAllLines(cbsLog);
                        int start = Math.Max(0, lines.Length - 20);
                        for (int i = start; i < lines.Length; i++)
                            result.Messages.Add("    " + lines[i]);
                    }
                    catch { }
                }

                switch (proc.ExitCode)
                {
                    case 0: result.Messages.Add("  \u2713 SFC: No se encontraron infracciones"); break;
                    case 1: result.Messages.Add("  \u2713 SFC: Archivos corruptos reparados"); break;
                    case 2: result.Messages.Add("  ! SFC: Archivos corruptos que no pudieron repararse"); break;
                    case 3: result.Messages.Add("  ! SFC: No se pudo realizar la verificaci\u00f3n"); break;
                    default: result.Messages.Add("  ! SFC c\u00f3digo: " + proc.ExitCode); break;
                }
            }
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Messages.Add("  Error: " + ex.Message);
        }
        return result;
    }

    /// <summary>
    /// Run DISM health checks (CheckHealth, ScanHealth, RestoreHealth).
    /// Replaces PS1 DISM block (~35 lines).
    /// </summary>
    public static CleanupResult RunDism(bool dryRun)
    {
        var result = new CleanupResult();
        result.Messages.Add("    NOTA: puede tardar entre 15-45 minutos");

        if (dryRun)
        {
            result.Messages.Add("  [DRY RUN] Se ejecutar\u00edan: CheckHealth, ScanHealth, RestoreHealth");
            return result;
        }

        var steps = new[]
        {
            new { Label = "Paso 1/3: CheckHealth...",   Args = "/Online /Cleanup-Image /CheckHealth" },
            new { Label = "Paso 2/3: ScanHealth...",    Args = "/Online /Cleanup-Image /ScanHealth" },
            new { Label = "Paso 3/3: RestoreHealth...", Args = "/Online /Cleanup-Image /RestoreHealth" }
        };

        foreach (var step in steps)
        {
            result.Messages.Add("");
            result.Messages.Add("  " + step.Label);
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "DISM.exe",
                    Arguments = step.Args,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    StandardOutputEncoding = System.Text.Encoding.UTF8
                };
                using (var proc = System.Diagnostics.Process.Start(psi))
                {
                    string output = proc.StandardOutput.ReadToEnd();
                    proc.WaitForExit();
                    foreach (string line in output.Split('\n'))
                    {
                        string t = line.Trim();
                        if (!string.IsNullOrEmpty(t))
                            result.Messages.Add("    " + t);
                    }
                }
            }
            catch (Exception ex)
            {
                result.Messages.Add("  Error: " + ex.Message);
            }
        }
        result.Messages.Add("");
        result.Messages.Add("  \u2713 DISM completado");
        return result;
    }

    // ── Internal helpers ────────────────────────────────────────────────────

    private static long GetDirectorySize(string path)
    {
        long size = 0;
        try
        {
            foreach (string file in SafeEnumerateFiles(path))
            {
                try { size += new System.IO.FileInfo(file).Length; }
                catch { }
            }
        }
        catch { }
        return size;
    }

    private static System.Collections.Generic.IEnumerable<string> SafeEnumerateFiles(string path)
    {
        var stack = new System.Collections.Generic.Stack<string>();
        stack.Push(path);
        while (stack.Count > 0)
        {
            string dir = stack.Pop();
            string[] files = null;
            try { files = System.IO.Directory.GetFiles(dir); } catch { }
            if (files != null)
                foreach (string f in files) yield return f;
            string[] dirs = null;
            try { dirs = System.IO.Directory.GetDirectories(dir); } catch { }
            if (dirs != null)
                foreach (string d in dirs) stack.Push(d);
        }
    }

    private static System.Collections.Generic.List<string> SafeEnumerateDirectories(string path)
    {
        // Return directories sorted deepest-first for safe bottom-up deletion
        var all = new System.Collections.Generic.List<string>();
        var stack = new System.Collections.Generic.Stack<string>();
        stack.Push(path);
        while (stack.Count > 0)
        {
            string dir = stack.Pop();
            string[] dirs = null;
            try { dirs = System.IO.Directory.GetDirectories(dir); } catch { }
            if (dirs != null)
            {
                foreach (string d in dirs)
                {
                    all.Add(d);
                    stack.Push(d);
                }
            }
        }
        all.Sort((a, b) => b.Length.CompareTo(a.Length)); // deepest first
        return all;
    }

    private static string[] SafeEnumerateEntries(string path)
    {
        try { return System.IO.Directory.GetFileSystemEntries(path); }
        catch { return new string[0]; }
    }
}
