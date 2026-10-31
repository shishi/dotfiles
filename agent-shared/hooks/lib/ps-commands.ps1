# shell_commands.py が PowerShell の本文を構文木にするスクリプト。標準入力で本文 (UTF-8) を受け取り、
# コマンド・Start-Process の束縛・文字列リテラルの位置・構文エラーを JSON で標準出力に書く。
# -EncodedCommand で渡すとコマンドラインが長くなり、scoop の shim を経由すると遅くなる・起動できないため、ファイルにしてある。
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$stdin = [Console]::OpenStandardInput()
$buffer = New-Object System.IO.MemoryStream
$stdin.CopyTo($buffer)
$source = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
function Test-Static($element) {
    return ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $element -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
}
function Get-Words($element) {
    if (Test-Static $element) { return , @([string]$element.Value) }
    if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
        $words = @('-' + $element.ParameterName)
        if ($null -ne $element.Argument) { $words += Get-Words $element.Argument }
        return , $words
    }
    if ($element -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $words = @()
        foreach ($item in $element.Elements) { $words += Get-Words $item }
        return , $words
    }
    return , @([string]$element.Extent.Text)
}
# Start-Process の FilePath / ArgumentList は PowerShell 自身の束縛規則で取り出す
function Get-StartProcess($command) {
    $binding = [System.Management.Automation.Language.StaticParameterBinder]::BindCommand($command, $true)
    $file = $binding.BoundParameters['FilePath']
    if ($null -eq $file) { return $null }
    $fileText = if (Test-Static $file.Value) { [string]$file.Value.Value } else { [string]$file.Value.Extent.Text }
    $arguments = @()
    $list = $binding.BoundParameters['ArgumentList']
    if ($null -ne $list) {
        # 引用した 1 つの文字列だけを値として読む。配列や式は表記のまま渡す
        $arguments = @(if (Test-Static $list.Value) { [string]$list.Value.Value } else { [string]$list.Value.Extent.Text })
    }
    return @{ file = $fileText; arguments = $arguments }
}
$commands = @()
foreach ($command in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    $words = @()
    foreach ($element in $command.CommandElements) { $words += Get-Words $element }
    $start = $null
    if (@('start-process', 'saps', 'start') -contains ([string]$command.GetCommandName()).ToLowerInvariant()) {
        $start = Get-StartProcess $command
    }
    $commands += , @{ words = $words; start = $start }
}
$messages = @()
foreach ($parseError in $errors) {
    $messages += ('{0}:{1}: {2}' -f $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message)
}
$json = ConvertTo-Json -InputObject @{ errors = $messages; commands = $commands } -Depth 6 -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
