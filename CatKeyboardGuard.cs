using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

internal static class CatKeyboardGuardHost
{
    private const string AppUserModelId = "CatKeyboardGuard.Desktop";

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [STAThread]
    private static int Main(string[] args)
    {
        SetCurrentProcessExplicitAppUserModelID(AppUserModelId);

        string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(baseDirectory, "CatKeyboardGuard.ps1");
        if (!File.Exists(scriptPath))
        {
            ShowError("找不到主程序：\r\n" + scriptPath);
            return 2;
        }

        bool selfTest = args.Length > 0 &&
            string.Equals(args[0], "--self-test", StringComparison.OrdinalIgnoreCase);

        try
        {
            InitialSessionState sessionState = InitialSessionState.CreateDefault();
            sessionState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace runspace = RunspaceFactory.CreateRunspace(sessionState))
            {
                runspace.ApartmentState = System.Threading.ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                runspace.Open();

                using (PowerShell powershell = PowerShell.Create())
                {
                    powershell.Runspace = runspace;
                    powershell.AddCommand(scriptPath);
                    if (selfTest)
                        powershell.AddParameter("SelfTest");

                    powershell.Invoke();
                    if (powershell.HadErrors)
                    {
                        StringBuilder details = new StringBuilder();
                        foreach (ErrorRecord error in powershell.Streams.Error)
                            details.AppendLine(error.ToString());

                        ReportError("程序启动失败。\r\n\r\n" + details.ToString().Trim(), selfTest);
                        return 1;
                    }

                    if (selfTest)
                        return 0;
                }
            }

            return 0;
        }
        catch (Exception exception)
        {
            ReportError("程序启动失败。\r\n\r\n" + exception.ToString(), selfTest);
            return 1;
        }
    }

    private static void ShowError(string message)
    {
        MessageBox.Show(
            message,
            "猫咪键盘守护",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }

    private static void ReportError(string message, bool selfTest)
    {
        if (selfTest)
            Console.Error.WriteLine(message);
        else
            ShowError(message);
    }
}
