[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$PublicKeyPath,

    [Parameter(Mandatory)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DinoSupportLauncherSource {
    return @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class Program
{
    private const string PayloadName = "DinoSupport.payload.zip";

    [STAThread]
    private static int Main()
    {
        string temporaryDirectory = Path.Combine(Path.GetTempPath(), "DinoSupport-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(temporaryDirectory);
            ExtractPayload(temporaryDirectory);

            string runner = Path.Combine(temporaryDirectory, "DinoSupport.ps1");
            string manifest = Path.Combine(temporaryDirectory, "task.json");
            string publicKey = Path.Combine(temporaryDirectory, "support-public-key.xml");
            string output = Path.ChangeExtension(Assembly.GetExecutingAssembly().Location, ".result.json");
            string powershell = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell\\v1.0\\powershell.exe");
            if (!File.Exists(powershell))
            {
                throw new InvalidOperationException("Windows PowerShell 5.1 was not found. DinoSupport cannot run this package.");
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = powershell;
            startInfo.Arguments = "-NoLogo -NoProfile -File \"" + runner + "\" -ManifestPath \"" + manifest + "\" -PublicKeyPath \"" + publicKey + "\" -OutputPath \"" + output + "\"";
            startInfo.WorkingDirectory = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = false;

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "DinoSupport could not start", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            try
            {
                if (Directory.Exists(temporaryDirectory))
                {
                    Directory.Delete(temporaryDirectory, true);
                }
            }
            catch
            {
                MessageBox.Show("DinoSupport stopped, but Windows could not remove its temporary files. Please delete: " + temporaryDirectory, "DinoSupport cleanup needed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }

    private static void ExtractPayload(string destinationDirectory)
    {
        using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadName))
        {
            if (resource == null) throw new InvalidOperationException("The DinoSupport package payload is missing.");
            using (ZipArchive archive = new ZipArchive(resource, ZipArchiveMode.Read))
            {
                string destinationRoot = Path.GetFullPath(destinationDirectory) + Path.DirectorySeparatorChar;
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    if (String.IsNullOrEmpty(entry.Name)) continue;
                    string destination = Path.GetFullPath(Path.Combine(destinationDirectory, entry.FullName));
                    if (!destination.StartsWith(destinationRoot, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidOperationException("The DinoSupport package contains an unsafe file path.");
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    entry.ExtractToFile(destination, false);
                }
            }
        }
    }
}
'@
}

function New-DinoSupportPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ManifestPath,
        [Parameter(Mandatory)] [string]$PublicKeyPath,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    if ($env:OS -ne 'Windows_NT') { throw 'DinoSupport packages can only be built on Windows.' }
    $runnerDirectory = Join-Path $PSScriptRoot '..' 'runner'
    $runnerFiles = @('DinoSupport.ps1', 'Consent.psm1', 'Evidence.psm1', 'NativeAutomation.psm1', 'TaskManifest.psm1')
    foreach ($file in $runnerFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $runnerDirectory $file) -PathType Leaf)) { throw "Required runner file is missing: $file" }
    }

    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    if ([IO.Path]::GetExtension($resolvedOutput) -ne '.exe') { throw 'OutputPath must end in .exe.' }
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { throw 'The output directory does not exist.' }
    if (Test-Path -LiteralPath $resolvedOutput) { throw 'OutputPath already exists; choose a new package filename.' }

    $stagingDirectory = Join-Path ([IO.Path]::GetTempPath()) ("DinoSupport-package-" + [guid]::NewGuid().ToString('N'))
    $payloadPath = Join-Path ([IO.Path]::GetTempPath()) ("DinoSupport-payload-" + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
        foreach ($file in $runnerFiles) { Copy-Item -LiteralPath (Join-Path $runnerDirectory $file) -Destination (Join-Path $stagingDirectory $file) -Force }
        Copy-Item -LiteralPath $ManifestPath -Destination (Join-Path $stagingDirectory 'task.json') -Force
        Copy-Item -LiteralPath $PublicKeyPath -Destination (Join-Path $stagingDirectory 'support-public-key.xml') -Force
        Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $stagingDirectory -File | Select-Object -ExpandProperty FullName) -DestinationPath $payloadPath -CompressionLevel Optimal

        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Add-Type -AssemblyName Microsoft.CSharp
        $parameters = [CodeDom.Compiler.CompilerParameters]::new()
        $parameters.GenerateExecutable = $true
        $parameters.GenerateInMemory = $false
        $parameters.OutputAssembly = $resolvedOutput
        $parameters.CompilerOptions = '/target:winexe /optimize+'
        [void]$parameters.ReferencedAssemblies.Add('System.dll')
        [void]$parameters.ReferencedAssemblies.Add('System.Windows.Forms.dll')
        [void]$parameters.ReferencedAssemblies.Add('System.IO.Compression.dll')
        [void]$parameters.ReferencedAssemblies.Add('System.IO.Compression.FileSystem.dll')
        [void]$parameters.EmbeddedResources.Add("$payloadPath,DinoSupport.payload.zip")
        $provider = [Microsoft.CSharp.CSharpCodeProvider]::new()
        try { $compile = $provider.CompileAssemblyFromSource($parameters, (Get-DinoSupportLauncherSource)) } finally { $provider.Dispose() }
        if ($compile.Errors.HasErrors) {
            $details = @($compile.Errors | Where-Object { -not $_.IsWarning } | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw "DinoSupport package compilation failed:$([Environment]::NewLine)$details"
        }
        if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) { throw 'DinoSupport package compilation did not create an executable.' }
        return Get-Item -LiteralPath $resolvedOutput
    } finally {
        if (Test-Path -LiteralPath $stagingDirectory) { Remove-Item -LiteralPath $stagingDirectory -Recurse -Force }
        if (Test-Path -LiteralPath $payloadPath) { Remove-Item -LiteralPath $payloadPath -Force }
    }
}

New-DinoSupportPackage -ManifestPath $ManifestPath -PublicKeyPath $PublicKeyPath -OutputPath $OutputPath
