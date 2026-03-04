using System;
using System.ComponentModel;
using System.IO;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

/// <summary>
/// SysOpt.DiskEngine — Motor de escaneo de disco y modelos de datos del Explorador.
/// Extraído del Add-Type inline de SysOpt v2.5.0 (línea 261).
/// Contiene: DiskItem_v211, DiskItemToggle_v230, ScanCtl211, PScanner211
/// Reemplaza: Add-Type @" ... "@ dentro del guard DiskItem_v211
/// Uso en PS:  Add-Type -Path ".\libs\SysOpt.DiskEngine.dll"
/// </summary>

// ── [RAM-01] DiskItem_v211: modelo de datos PURO — sin INotifyPropertyChanged ──
// Las propiedades de toggle (ToggleVisibility / ToggleIcon) se separan a
// DiskItemToggle_v230, un wrapper INPC ligero, para no retener event listeners
// ni PropertyChangedEventArgs en los (potencialmente cientos de miles) de items.
public class DiskItem_v211
{
    public string DisplayName       { get; set; }
    public string FullPath          { get; set; }
    public string ParentPath        { get; set; }
    public long   SizeBytes         { get; set; }
    public string SizeStr           { get; set; }
    public string SizeColor         { get; set; }
    public string PctStr            { get; set; }
    public string FileCount         { get; set; }
    public int    DirCount          { get; set; }
    public bool   IsDir             { get; set; }
    public bool   HasChildren       { get; set; }
    public string Icon              { get; set; }
    public string Indent            { get; set; }
    public double BarWidth          { get; set; }
    public string BarColor          { get; set; }
    public double TotalPct          { get; set; }
    public int    Depth             { get; set; }

    // Toggle state inline (no INPC — la UI los lee desde DiskItemToggle_v230)
    public string ToggleVisibility  { get; set; }
    public string ToggleIcon        { get; set; }

    public DiskItem_v211()
    {
        ToggleVisibility = "Collapsed";
        ToggleIcon       = "\u25B6";
    }
}

// ── [RAM-01] DiskItemToggle_v230: wrapper INPC solo para colapso/expansión ──
// La UI lo usa como DataContext del botón toggle.
// Referencia al DiskItem_v211 para leer metadatos sin duplicarlos.
public class DiskItemToggle_v230 : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler PropertyChanged;

    private void N(string p)
    {
        if (PropertyChanged != null)
            PropertyChanged(this, new PropertyChangedEventArgs(p));
    }

    public DiskItem_v211 Item { get; private set; }

    public DiskItemToggle_v230(DiskItem_v211 item)
    {
        Item = item;
    }

    public string ToggleVisibility
    {
        get { return Item.ToggleVisibility; }
        set
        {
            if (Item.ToggleVisibility != value)
            {
                Item.ToggleVisibility = value;
                N("ToggleVisibility");
            }
        }
    }

    public string ToggleIcon
    {
        get { return Item.ToggleIcon; }
        set
        {
            if (Item.ToggleIcon != value)
            {
                Item.ToggleIcon = value;
                N("ToggleIcon");
            }
        }
    }
}

// ── ScanCtl211: señales compartidas entre runspaces ──────────────────────────
// [CTK] Bridge: Stop getter ahora revisa _stop || _token.IsCancellationRequested
//       Así PScanner211 respeta CancellationToken sin cambiar su código interno.
//       Uso: [ScanCtl211]::SetToken([ScanTokenManager]::Token)
public static class ScanCtl211
{
    private static volatile bool   _stop     = false;
    public  static int             _doneRef  = 0;
    public  static int             _totalRef = 0;
    private static volatile string _current  = "";
    private static CancellationToken _token  = CancellationToken.None;

    /// <summary>
    /// True si se pidió detener via flag directo O via CancellationToken.
    /// PScanner211 lee esta propiedad — el bridge garantiza que Cancel() basta.
    /// </summary>
    public static bool Stop
    {
        get { return _stop || _token.IsCancellationRequested; }
        set { _stop = value; }
    }

    public static int    Done    { get { return System.Threading.Thread.VolatileRead(ref _doneRef);  } set { _doneRef   = value; } }
    public static int    Total   { get { return System.Threading.Thread.VolatileRead(ref _totalRef); } set { _totalRef  = value; } }
    public static string Current { get { return _current;  } set { _current   = value; } }

    /// <summary>Enlaza el token de ScanTokenManager para que PScanner211 respete CTK.</summary>
    public static void SetToken(CancellationToken token)
    {
        _token = token;
    }

    public static void Reset()
    {
        _stop     = false;
        _doneRef  = 0;
        _totalRef = 0;
        _current  = "";
        _token    = CancellationToken.None;
    }
}

// ── [A1] PScanner211: escaneo paralelo estilo TreeSize ────────────────────────
public static class PScanner211
{
    private const int MAX_DEPTH = 64; // evitar stack overflow en estructuras muy profundas

    public static long ScanDir(
        string path, int depth, string parentKey,
        ConcurrentQueue<object[]> q)
    {
        if (ScanCtl211.Stop)    return 0L;
        if (depth > MAX_DEPTH)  return 0L; // corta recursión excesiva

        string dName = Path.GetFileName(path);
        if (string.IsNullOrEmpty(dName)) dName = path;

        // Emitir placeholder inmediato para que la UI lo muestre enseguida
        q.Enqueue(new object[] { path, parentKey, dName, -1L, 0, 0, false, depth });

        long totalSize = 0L;
        int  fileCount = 0;

        // Sumar archivos del directorio actual
        try
        {
            string[] files = Directory.GetFiles(path);
            fileCount = files.Length;
            foreach (string f in files)
            {
                if (ScanCtl211.Stop) break;
                try { totalSize += new FileInfo(f).Length; } catch { }
            }
        }
        catch { }

        // Obtener subdirectorios
        string[] subDirs;
        try   { subDirs = Directory.GetDirectories(path); }
        catch { subDirs = new string[0]; }

        Interlocked.Add(ref ScanCtl211._totalRef, subDirs.Length);

        long[] subSizes = new long[subDirs.Length];

        // Paralelismo adaptativo: solo en niveles superficiales Y si quedan niveles
        if (depth <= 1 && subDirs.Length > 1 && depth + 1 < MAX_DEPTH)
        {
            Parallel.For(0, subDirs.Length,
                new ParallelOptions { MaxDegreeOfParallelism = 4 }, i =>
                {
                    if (ScanCtl211.Stop) return;
                    ScanCtl211.Current = Path.GetFileName(subDirs[i]);
                    subSizes[i]        = ScanDir(subDirs[i], depth + 1, path, q);
                    Interlocked.Increment(ref ScanCtl211._doneRef);
                });
        }
        else
        {
            for (int i = 0; i < subDirs.Length; i++)
            {
                if (ScanCtl211.Stop) break;
                ScanCtl211.Current = Path.GetFileName(subDirs[i]);
                subSizes[i]        = ScanDir(subDirs[i], depth + 1, path, q);
                Interlocked.Increment(ref ScanCtl211._doneRef);
            }
        }

        foreach (long s in subSizes) totalSize += s;

        // Emitir resultado final con tamaño real calculado
        q.Enqueue(new object[] { path, parentKey, dName, totalSize, fileCount, subDirs.Length, true, depth });
        return totalSize;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DiskResult — Result container for disk operations
// ═══════════════════════════════════════════════════════════════════════════════
public class DiskResult
{
    public double FreedMB        { get; set; }
    public int    FilesProcessed { get; set; }
    public int    Errors         { get; set; }
    public bool   Success        { get; set; }
    public string Summary        { get; set; }
    public System.Collections.Generic.List<string> Messages { get; set; }

    public DiskResult()
    {
        Messages = new System.Collections.Generic.List<string>();
        Success  = true;
        Summary  = "";
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DiskOptimizer — Volume optimization and CHKDSK scheduling
// ═══════════════════════════════════════════════════════════════════════════════
public class VolumeInfo
{
    public string DriveLetter  { get; set; }
    public double SizeGB       { get; set; }
    public double FreeGB       { get; set; }
    public string MediaType    { get; set; }
    public bool   IsSSD        { get; set; }
    public bool   IsNVMe       { get; set; }
}

public static class DiskOptimizer
{
    /// <summary>
    /// Enumerate fixed volumes with SSD/NVMe detection via WMI.
    /// </summary>
    public static VolumeInfo[] GetFixedVolumes()
    {
        var list = new System.Collections.Generic.List<VolumeInfo>();
        try
        {
            // Get logical disks (fixed only)
            using (var s = new System.Management.ManagementObjectSearcher(
                "SELECT DeviceID, Size, FreeSpace FROM Win32_LogicalDisk WHERE DriveType=3"))
            {
                foreach (System.Management.ManagementObject d in s.Get())
                {
                    string devId = (d["DeviceID"] ?? "").ToString(); // "C:"
                    if (string.IsNullOrEmpty(devId) || devId.Length < 2) continue;
                    string letter = devId.Substring(0, 1);
                    double sizeGB = Math.Round(Convert.ToDouble(d["Size"] ?? 0) / 1073741824.0, 2);
                    double freeGB = Math.Round(Convert.ToDouble(d["FreeSpace"] ?? 0) / 1073741824.0, 2);

                    // Detect SSD/NVMe
                    bool isSSD = false; bool isNVMe = false; string mediaType = "Unknown";
                    try
                    {
                        // Map LogicalDisk -> Partition -> DiskDrive
                        string q1 = "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='" + devId +
                                     "'} WHERE AssocClass=Win32_LogicalDiskToPartition";
                        using (var s2 = new System.Management.ManagementObjectSearcher(q1))
                        {
                            foreach (System.Management.ManagementObject part in s2.Get())
                            {
                                string q2 = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='" +
                                             part["DeviceID"] + "'} WHERE AssocClass=Win32_DiskDriveToDiskPartition";
                                using (var s3 = new System.Management.ManagementObjectSearcher(q2))
                                {
                                    foreach (System.Management.ManagementObject dd in s3.Get())
                                    {
                                        string model = (dd["Model"] ?? "").ToString();
                                        isNVMe = model.IndexOf("NVMe", StringComparison.OrdinalIgnoreCase) >= 0;
                                        mediaType = (dd["MediaType"] ?? "Unknown").ToString();
                                        // Try MSFT_PhysicalDisk for better SSD detection
                                        try
                                        {
                                            using (var s4 = new System.Management.ManagementObjectSearcher(
                                                @"root\Microsoft\Windows\Storage",
                                                "SELECT MediaType FROM MSFT_PhysicalDisk"))
                                            {
                                                foreach (System.Management.ManagementObject pd in s4.Get())
                                                {
                                                    ushort mt = Convert.ToUInt16(pd["MediaType"]);
                                                    if (mt == 4) isSSD = true; // 4 = SSD
                                                }
                                            }
                                        }
                                        catch { }
                                        if (isNVMe) isSSD = true;
                                        break;
                                    }
                                }
                                break;
                            }
                        }
                    }
                    catch { }

                    list.Add(new VolumeInfo
                    {
                        DriveLetter = letter,
                        SizeGB = sizeGB,
                        FreeGB = freeGB,
                        MediaType = (isSSD ? "SSD" : mediaType) + (isNVMe ? " (NVMe)" : ""),
                        IsSSD = isSSD,
                        IsNVMe = isNVMe
                    });
                }
            }
        }
        catch { }
        return list.ToArray();
    }

    /// <summary>
    /// Optimize a single volume via defrag.exe /O (auto-detects SSD vs HDD).
    /// Returns messages for console output.
    /// </summary>
    public static DiskResult OptimizeVolume(string driveLetter, bool isSSD, bool dryRun)
    {
        var result = new DiskResult();
        if (dryRun)
        {
            result.Messages.Add("  [DRY RUN] Se ejecutar\u00eda: " +
                (isSSD ? "TRIM (defrag /L)" : "Defrag (defrag /O)"));
            return result;
        }
        try
        {
            string args = isSSD ? (driveLetter + ": /L") : (driveLetter + ": /O");
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "defrag.exe",
                Arguments = args,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var proc = System.Diagnostics.Process.Start(psi))
            {
                string output = proc.StandardOutput.ReadToEnd();
                proc.WaitForExit(600000); // 10 min timeout
                foreach (string line in output.Split('\n'))
                {
                    string t = line.Trim();
                    if (!string.IsNullOrEmpty(t))
                        result.Messages.Add("    " + t);
                }
                result.Success = proc.ExitCode == 0;
            }
            result.Messages.Add("  \u2713 " + (isSSD ? "TRIM completado" : "Desfragmentaci\u00f3n completada"));
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Messages.Add("  \u2717 Error: " + ex.Message);
        }
        return result;
    }

    /// <summary>
    /// Schedule CHKDSK via fsutil dirty set.
    /// </summary>
    public static DiskResult ScheduleChkdsk(string drive, bool dryRun)
    {
        var result = new DiskResult();
        if (dryRun)
        {
            result.Messages.Add("  [DRY RUN] Se programar\u00eda CHKDSK en el pr\u00f3ximo reinicio");
            return result;
        }
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "fsutil.exe",
                Arguments = "dirty set " + drive + ":",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var proc = System.Diagnostics.Process.Start(psi))
            {
                string output = proc.StandardOutput.ReadToEnd();
                proc.WaitForExit(15000);
                foreach (string line in output.Split('\n'))
                {
                    string t = line.Trim();
                    if (!string.IsNullOrEmpty(t))
                        result.Messages.Add("    " + t);
                }
            }
            result.Messages.Add("  \u2713 CHKDSK programado \u2014 se ejecutar\u00e1 en el pr\u00f3ximo reinicio");
            result.Messages.Add("  NOTA: El sistema debe reiniciarse para que CHKDSK se ejecute");
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Messages.Add("  Error: " + ex.Message);
        }
        return result;
    }
}
