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
public static class ScanCtl211
{
    private static volatile bool   _stop     = false;
    public  static int             _doneRef  = 0;
    public  static int             _totalRef = 0;
    private static volatile string _current  = "";

    public static bool   Stop    { get { return _stop;     } set { _stop     = value; } }
    public static int    Done    { get { return _doneRef;  } set { _doneRef   = value; } }
    public static int    Total   { get { return _totalRef; } set { _totalRef  = value; } }
    public static string Current { get { return _current;  } set { _current   = value; } }

    public static void Reset()
    {
        _stop     = false;
        _doneRef  = 0;
        _totalRef = 0;
        _current  = "";
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
