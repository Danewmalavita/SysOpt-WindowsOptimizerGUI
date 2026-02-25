using System;
using System.Runtime.InteropServices;

/// <summary>
/// SysOpt.WseTrim — Working Set trim via SetProcessWorkingSetSize.
/// Extraído del Add-Type inline de SysOpt v2.5.0 (línea 6637).
/// Clase original: WseTrim2 (nombre compacto inline para evitar colisiones).
/// Renombrada a WseTrim para uso desde DLL externo.
/// Reemplaza: Add-Type -TypeDefinition @' ... '@ -ErrorAction SilentlyContinue
/// Uso en PS:  Add-Type -Path ".\libs\SysOpt.WseTrim.dll"
///             [WseTrim]::TrimCurrentProcess()
/// </summary>
public class WseTrim
{
    [DllImport("kernel32.dll")]
    private static extern bool SetProcessWorkingSetSize(IntPtr hProcess, IntPtr dwMinimumWorkingSetSize, IntPtr dwMaximumWorkingSetSize);

    /// <summary>
    /// Recorta el Working Set del proceso actual pasando -1 a min y max.
    /// Windows libera las páginas no esenciales de vuelta al SO.
    /// </summary>
    public static void TrimCurrentProcess()
    {
        var proc = System.Diagnostics.Process.GetCurrentProcess();
        SetProcessWorkingSetSize(proc.Handle, new IntPtr(-1), new IntPtr(-1));
    }

    /// <summary>
    /// Sobrecarga que acepta un handle de proceso externo.
    /// </summary>
    public static void TrimProcess(IntPtr hProcess)
    {
        SetProcessWorkingSetSize(hProcess, new IntPtr(-1), new IntPtr(-1));
    }
}
