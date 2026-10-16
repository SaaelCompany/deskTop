using System;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("DesktopSwitch")]
[assembly: AssemblyProduct("DesktopSwitch")]
[assembly: AssemblyCompany("SaaelCompany")]
[assembly: AssemblyVersion("1.2.41.0")]
[assembly: AssemblyFileVersion("1.2.41.0")]

internal static class DesktopSwitchHost {
    const string Title = "\u0421\u0435\u0440\u0432\u0438\u0441\u043d\u0430\u044f \u0441\u043b\u0443\u0436\u0431\u0430";

    [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AllocConsole();

    [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AttachConsole(int processId);

    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    static extern bool SetConsoleOutputCP(uint codePage);

    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    static extern bool SetConsoleCP(uint codePage);

    [STAThread]
    static int Main(string[] args) {
        bool status = false;
        bool once = false;
        bool stop = false;
        bool help = false;
        try {
            for (int i = 0; i < args.Length; i++) {
                string arg = args[i] ?? "";
                if (Same(arg, "-Status") || Same(arg, "/Status")) status = true;
                else if (Same(arg, "-Once") || Same(arg, "/Once")) once = true;
                else if (Same(arg, "-Stop") || Same(arg, "/Stop")) stop = true;
                else if (Same(arg, "-Help") || Same(arg, "/?") || Same(arg, "-?")) help = true;
                else {
                    Fail("\u041d\u0435\u0438\u0437\u0432\u0435\u0441\u0442\u043d\u044b\u0439 \u043f\u0430\u0440\u0430\u043c\u0435\u0442\u0440: " + arg);
                    return 1;
                }
            }
            if (stop) {
                StopOtherCopies();
                return 0;
            }
            string exe = Application.ExecutablePath;
            string dir = Path.GetDirectoryName(exe);
            string script;
            try {
                script = PrepareScript(dir);
            } catch (Exception ex) {
                Note(ex.ToString());
                Fail("\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u043e\u0434\u0433\u043e\u0442\u043e\u0432\u0438\u0442\u044c \u0444\u0430\u0439\u043b\u044b \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u044b.\r\n\r\n" + ex.Message);
                return 1;
            }
            if (help) {
                ShowConsole(Usage(script));
                return 0;
            }
            Directory.SetCurrentDirectory(Path.GetDirectoryName(script));
            bool ownConsole = false;
            if (status) ownConsole = OpenConsole();
            Note("start " + string.Join(" ", args));
            int code = RunScript(script, status, once);
            if (status && ownConsole) {
                Console.WriteLine();
                Console.WriteLine("\u041d\u0430\u0436\u043c\u0438\u0442\u0435 Enter");
                Console.ReadLine();
            }
            return code;
        } catch (Exception ex) {
            Note(ex.ToString());
            Fail(ex.Message);
            return 1;
        }
    }

    static int RunScript(string script, bool status, bool once) {
        InitialSessionState state = InitialSessionState.CreateDefault();
        using (Runspace runspace = RunspaceFactory.CreateRunspace(state)) {
            runspace.ApartmentState = ApartmentState.STA;
            runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
            runspace.Open();
            using (PowerShell ps = PowerShell.Create()) {
                ps.Runspace = runspace;
                ps.AddScript("try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch { }; try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }");
                ps.Invoke();
                ps.Commands.Clear();
                ps.Streams.Error.Clear();
                var command = new StringBuilder();
                command.Append(". ").Append(PsQuote(script));
                if (status) command.Append(" -Status");
                if (once) command.Append(" -Once");
                ps.AddScript(command.ToString(), false);
                try {
                    ps.Invoke();
                } catch (Exception ex) {
                    if (IsExit(ex)) return 0;
                    Note(ex.ToString());
                    if (!status) Fail(ex.Message);
                    else Console.Error.WriteLine(ex.Message);
                    return 1;
                }
                return 0;
            }
        }
    }

    static void StopOtherCopies() {
        int self = Process.GetCurrentProcess().Id;
        foreach (Process proc in Process.GetProcessesByName("DesktopSwitch")) {
            if (proc.Id == self) continue;
            try { proc.Kill(); } catch { }
        }
    }

    static bool OpenConsole() {
        bool attached = AttachConsole(-1);
        if (!attached) AllocConsole();
        SetConsoleOutputCP(65001);
        SetConsoleCP(65001);
        try {
            var writer = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true };
            var error = new StreamWriter(Console.OpenStandardError(), new UTF8Encoding(false)) { AutoFlush = true };
            Console.SetOut(writer);
            Console.SetError(error);
        } catch { }
        return !attached;
    }

    static void ShowConsole(string text) {
        bool own = OpenConsole();
        Console.WriteLine(text);
        if (own) {
            Console.WriteLine();
            Console.WriteLine("\u041d\u0430\u0436\u043c\u0438\u0442\u0435 Enter");
            Console.ReadLine();
        }
    }

    static string Usage(string script) {
        var text = new StringBuilder();
        text.AppendLine("DesktopSwitch 1.2.41");
        text.AppendLine("\u041a\u0440\u0430\u0441\u043d\u0430\u044f \u043a\u043d\u043e\u043f\u043a\u0430, \u043a\u043e\u0433\u0434\u0430 \u043d\u0435\u0442 \u0438\u043d\u0442\u0435\u0440\u043d\u0435\u0442\u0430. \u041d\u0430\u0436\u0430\u0442\u0438\u0435 \u043e\u0442\u043a\u0440\u044b\u0432\u0430\u0435\u0442 C:\\Users\\Public\\Desktop.");
        text.AppendLine(script);
        text.AppendLine("DesktopSwitch.exe");
        text.AppendLine("DesktopSwitch.exe -Status");
        text.AppendLine("DesktopSwitch.exe -Once");
        text.AppendLine("DesktopSwitch.exe -Stop");
        return text.ToString();
    }

    static bool ScriptsReady(string directory) {
        return File.Exists(Path.Combine(directory, "DesktopSwitch.ps1"))
            && File.Exists(Path.Combine(directory, "DesktopSwitch.Logic.ps1"))
            && File.Exists(Path.Combine(directory, "DesktopSwitch.Widget.ps1"));
    }

    static string PrepareScript(string exeDir) {
        if (ScriptsReady(exeDir)) {
            if (CanWrite(exeDir)) {
                try { RefreshScripts(exeDir); } catch (Exception ex) { Note("script refresh skipped: " + ex.Message); }
            }
            return Path.Combine(exeDir, "DesktopSwitch.ps1");
        }
        string dest = CanWrite(exeDir)
            ? exeDir
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DesktopSwitch", "app");
        Directory.CreateDirectory(dest);
        RefreshScripts(dest);
        Note("extracted scripts to " + dest);
        return Path.Combine(dest, "DesktopSwitch.ps1");
    }

    static void RefreshScripts(string directory) {
        ExtractResource("DesktopSwitch.ps1", directory);
        ExtractResource("DesktopSwitch.Logic.ps1", directory);
        ExtractResource("DesktopSwitch.Widget.ps1", directory);
    }

    static void ExtractResource(string name, string directory) {
        using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
            if (source == null) throw new FileNotFoundException(name);
            using (FileStream dest = File.Create(Path.Combine(directory, name))) {
                source.CopyTo(dest);
            }
        }
    }

    static bool CanWrite(string directory) {
        try {
            string probe = Path.Combine(directory, ".desktopswitch-write");
            File.WriteAllText(probe, "ok");
            File.Delete(probe);
            return true;
        } catch {
            return false;
        }
    }

    static void Fail(string text) {
        Note(text);
        try {
            MessageBox.Show(text, Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        } catch { }
    }

    static void Note(string text) {
        try {
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DesktopSwitch");
            Directory.CreateDirectory(root);
            File.AppendAllText(Path.Combine(root, "host.log"), DateTime.Now.ToString("s") + " " + text + Environment.NewLine, new UTF8Encoding(false));
        } catch { }
    }

    static bool IsExit(Exception ex) {
        for (Exception item = ex; item != null; item = item.InnerException) {
            if (string.Equals(item.GetType().Name, "ExitException", StringComparison.Ordinal)) return true;
        }
        return false;
    }

    static bool Same(string value, string expected) {
        return string.Equals(value, expected, StringComparison.OrdinalIgnoreCase);
    }

    static string PsQuote(string value) {
        return "'" + (value ?? "").Replace("'", "''") + "'";
    }
}
