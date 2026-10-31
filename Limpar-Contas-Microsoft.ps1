<#
    Limpar-Contas-Microsoft.ps1
    Prepara o computador para o aluno seguinte, no perfil do utilizador
    atual do Windows 11:

    - Remove contas Microsoft 365 / Teams guardadas (credenciais, caches de
      autenticação, identidades do Office e sessão do Teams).
    - Termina as sessões iniciadas no Google Chrome e no Microsoft Edge
      (mantém marcadores, histórico e palavras-passe guardadas).
    - Repõe o tema claro e o fundo original do Windows 11 (sempre o mesmo).
    - Repõe as definições do rato (dextro) e os ponteiros originais.
    - Repõe o teclado: só Português (Portugal), teclado Português, e as
      teclas de acessibilidade desligadas.
    - Deixa no ambiente de trabalho só os ícones originais (Este PC,
      Reciclagem, Google Chrome e Microsoft Edge), com nomes e imagens
      originais, e o tamanho dos ícones (ícones médios). Tudo o resto é
      retirado e guardado durante 14 dias em
      %LOCALAPPDATA%\LimpezaSala\Retirados do ambiente de trabalho
    - Repõe a barra de tarefas e o menu Iniciar de origem.
    - Repõe o formato regional (Português - Portugal) e o fuso horário.
    - Põe o som em silêncio (volume a 50% para quando for ligado).
    - Trata também o Opera, se estiver instalado (sessões, zoom e atalho
      em navegação privada).
    - Liga o Wi-Fi, se o computador tiver placa de rede sem fios.
    - Como administrador ou SYSTEM: navegador predefinido Edge, aplicações
      afixadas na barra de tarefas, planos de energia de origem e bloqueio
      dos sites da lista Sites-Bloqueados.txt (Chrome, Edge e ficheiro
      hosts), com o DNS seguro desligado e o DNS das placas automático.
    - Define https://aefernandocasimiro.wordpress.com/ como página inicial
      do Google Chrome e do Microsoft Edge.
    - Faz o Google Chrome e o Microsoft Edge abrirem sempre em sessão
      anónima (navegação anónima / InPrivate).
    - Repõe as definições de visualização: resolução, orientação, escala,
      tamanho do texto, alto contraste, filtros de cor, lupa e zoom do
      Chrome e do Edge.

    Não precisa de direitos de administrador e não retira o computador do
    domínio da escola. Só mexe nos ficheiros do ambiente de trabalho, que
    retira para a pasta indicada acima (não os apaga de imediato).
    Depois de correr manualmente, é necessário terminar sessão no Windows.

    Modo de administração (-Administracao): usado pelo Instalar-Arranque.bat
    quando é executado como administrador. Define a página inicial do Chrome
    e do Edge e a sessão anónima do Chrome e do Edge por política, para todos os
    utilizadores, liga as placas Wi-Fi e termina.

    Modo de sistema (-Sistema): usado pela tarefa agendada "Limpeza da sala -
    Rede", que corre como SYSTEM sempre que o computador arranca. Liga as
    placas Wi-Fi que estejam desativadas. Registo em
    %ProgramData%\LimpezaSala\registo-sistema.txt

    Modo automático (-Automatico): não faz perguntas, corre escondido e é o
    modo usado quando o script é lançado no início de cada sessão do Windows
    (ver Instalar-Arranque.bat). Guarda um registo em
    %LOCALAPPDATA%\LimpezaSala\ultimo-registo.txt
#>

param([switch]$Automatico, [switch]$Administracao, [switch]$Sistema, [switch]$Confirmado, [switch]$SemAtualizar)

$VERSAO = '2.8'

# Página inicial da escola para o Google Chrome e o Microsoft Edge
$PAGINA = 'https://aefernandocasimiro.wordpress.com/'

$eAdministrador = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Define a página inicial por política (só funciona como administrador)
function Definir-PaginaInicialPorPolitica {
    $chaves = @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge')
    foreach ($ch in $chaves) {
        if (-not (Test-Path $ch)) { New-Item -Path $ch -Force | Out-Null }
        Set-ItemProperty -Path $ch -Name HomepageLocation     -Value $PAGINA
        Set-ItemProperty -Path $ch -Name HomepageIsNewTabPage -Value 0 -Type DWord
        Set-ItemProperty -Path $ch -Name ShowHomeButton       -Value 1 -Type DWord
        Set-ItemProperty -Path $ch -Name RestoreOnStartup     -Value 4 -Type DWord   # abrir páginas específicas
        $urls = "$ch\RestoreOnStartupURLs"
        if (Test-Path $urls) { Remove-Item -Path $urls -Recurse -Force }
        New-Item -Path $urls -Force | Out-Null
        Set-ItemProperty -Path $urls -Name '1' -Value $PAGINA
    }
    # Abrir sempre em sessão anónima: Chrome (navegação anónima) e Edge (InPrivate)
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name IncognitoModeAvailability -Value 2 -Type DWord
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name InPrivateModeAvailability -Value 2 -Type DWord
}

$ErrorActionPreference = 'SilentlyContinue'

# Ligar as placas de rede Wi-Fi (precisa de direitos de administrador ou de
# correr como SYSTEM: é usado pela tarefa agendada criada pelo instalador)
# Retira de uma pasta do ambiente de trabalho tudo o que não é original
# (ficheiros, pastas e atalhos) para uma pasta de recuperação, onde fica
# guardado durante 14 dias. Escreve no registo cada item retirado ou falhado.
$ATALHOS_ORIGINAIS = @('Google Chrome.lnk', 'Microsoft Edge.lnk', 'Opera Browser.lnk')
function Limpar-PastaAmbienteTrabalho([string]$pasta, [string]$baseRetirados) {
    $resultado = [pscustomobject]@{ Movidos = 0; Falhados = 0 }
    if (-not $pasta -or -not (Test-Path -LiteralPath $pasta)) { return $resultado }
    $retirados = Join-Path $baseRetirados (Get-Date -Format 'yyyy-MM-dd HH-mm-ss')
    $itens = @(Get-ChildItem -LiteralPath $pasta -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ne 'desktop.ini' -and
        -not ($_.Attributes -band [IO.FileAttributes]::System) -and
        $ATALHOS_ORIGINAIS -notcontains $_.Name
    })
    Write-Host "      ${pasta}: $($itens.Count) item(ns) a retirar."
    foreach ($item in $itens) {
        try {
            if (-not (Test-Path -LiteralPath $retirados)) {
                New-Item -Path $retirados -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            $destino = Join-Path $retirados $item.Name
            if (Test-Path -LiteralPath $destino) {
                $destino = Join-Path $retirados ("{0} ({1}){2}" -f $item.BaseName, [guid]::NewGuid().ToString('N').Substring(0, 6), $item.Extension)
            }
            Move-Item -LiteralPath $item.FullName -Destination $destino -Force -ErrorAction Stop
            $resultado.Movidos++
            Write-Host "        retirado: $($item.Name)"
        } catch {
            $resultado.Falhados++
            Write-Host "        NÃO retirado: $($item.Name) - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    # Apagar o que foi retirado há mais de 14 dias
    if (Test-Path -LiteralPath $baseRetirados) {
        Get-ChildItem -LiteralPath $baseRetirados -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-14) } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $resultado
}

function Ligar-PlacasWiFi {
    $wifi = Get-NetAdapter -Physical | Where-Object {
        $_.NdisPhysicalMedium -eq 9 -or $_.PhysicalMediaType -match '802\.11' -or
        $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11'
    }
    if (-not $wifi) { Write-Host 'Não existe placa de rede Wi-Fi neste computador.'; return }
    Set-Service -Name WlanSvc -StartupType Automatic
    Start-Service -Name WlanSvc
    foreach ($a in $wifi) {
        if ($a.Status -eq 'Disabled') {
            Enable-NetAdapter -Name $a.Name -Confirm:$false
            Write-Host "Placa Wi-Fi ligada: $($a.Name) ($($a.InterfaceDescription))"
        } else {
            Write-Host "Placa Wi-Fi já estava ligada: $($a.Name)"
        }
    }
}

# Direção da roda do rato: rodar para baixo desce a página (valor de origem).
# O Windows guarda esta opção em cada rato (FlipFlopWheel), numa zona do
# registo que só o administrador ou o SYSTEM podem alterar.
function Repor-DirecaoRodaRato {
    $alterados = 0
    Get-ChildItem -Path 'HKLM:\SYSTEM\CurrentControlSet\Enum\HID' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -eq 'Device Parameters' } | ForEach-Object {
            $props = Get-ItemProperty -Path $_.PSPath
            $mudou = $false
            foreach ($nome in 'FlipFlopWheel', 'FlipFlopHScroll') {
                if ($null -ne $props.$nome -and $props.$nome -ne 0) {
                    Set-ItemProperty -Path $_.PSPath -Name $nome -Value 0 -Type DWord
                    $mudou = $true
                }
            }
            if ($mudou) {
                $alterados++
                $instancia = ($_.PSParentPath -split '\\Enum\\', 2)[1]
                Write-Host "Roda do rato reposta: $instancia"
                pnputil /restart-device "$instancia" | Out-Null   # aplicar sem reiniciar
            }
        }
    if ($alterados -eq 0) { Write-Host 'Roda do rato: já estava na direção de origem.' }
}

# Sites bloqueados: lê a lista Sites-Bloqueados.txt (um endereço por linha)
# e bloqueia-os no Chrome e no Edge (política URLBlocklist) e em todos os
# programas (ficheiro hosts do Windows). Precisa de administrador ou SYSTEM.
$INICIO_HOSTS = '# >>> Limpeza da sala - sites bloqueados (nao alterar a mao)'
$FIM_HOSTS    = '# <<< Limpeza da sala - sites bloqueados'
function Ler-SitesBloqueados([string]$ficheiro) {
    $dominios = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $ficheiro)) { return ,$dominios }
    foreach ($linha in [IO.File]::ReadAllLines($ficheiro)) {
        $d = ($linha -replace '#.*$', '').Trim().ToLowerInvariant()
        if (-not $d) { continue }
        $d = $d -replace '^[a-z]+://', ''          # retirar http:// ou https://
        $d = ($d -split '[/:?]')[0]                # retirar caminho e porta
        $d = $d -replace '^\*\.', '' -replace '^www\.', ''
        if ($d -match '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' -and -not $dominios.Contains($d)) {
            $dominios.Add($d)
        } else {
            if (-not $dominios.Contains($d)) { Write-Host "Linha ignorada na lista de sites: $linha" }
        }
    }
    return ,$dominios
}

function Aplicar-SitesBloqueados {
    $ficheiro = "$env:ProgramData\LimpezaSala\Sites-Bloqueados.txt"
    $dominios = Ler-SitesBloqueados $ficheiro

    # 1) Chrome e Edge: política de bloqueio de endereços (bloqueia o domínio
    #    e todos os subdomínios) e DNS seguro desligado, para não escapar ao
    #    filtro da rede
    foreach ($ch in 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge') {
        if (-not (Test-Path $ch)) { New-Item -Path $ch -Force | Out-Null }
        Set-ItemProperty -Path $ch -Name DnsOverHttpsMode -Value 'off'
        $lista = "$ch\URLBlocklist"
        if (Test-Path $lista) { Remove-Item -Path $lista -Recurse -Force }
        if ($dominios.Count -gt 0) {
            New-Item -Path $lista -Force | Out-Null
            $n = 1
            foreach ($d in $dominios) { Set-ItemProperty -Path $lista -Name "$n" -Value $d; $n++ }
        }
    }

    # 2) Ficheiro hosts: bloqueia também o Opera e os outros programas
    $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
    $linhas = @()
    $ansi = [System.Text.Encoding]::Default   # o ficheiro hosts usa a codificação do Windows
    if (Test-Path $hosts) { $linhas = @([IO.File]::ReadAllLines($hosts, $ansi)) }
    $fora = @(); $dentro = $false
    foreach ($l in $linhas) {
        if ($l -eq $INICIO_HOSTS) { $dentro = $true; continue }
        if ($l -eq $FIM_HOSTS)    { $dentro = $false; continue }
        if (-not $dentro) { $fora += $l }
    }
    while ($fora.Count -gt 0 -and -not $fora[-1].Trim()) { $fora = $fora[0..($fora.Count - 2)] }
    $novo = @($fora)
    if ($dominios.Count -gt 0) {
        $novo += ''
        $novo += $INICIO_HOSTS
        foreach ($d in $dominios) {
            $novo += "0.0.0.0 $d"
            $novo += "0.0.0.0 www.$d"
        }
        $novo += $FIM_HOSTS
    }
    $texto = ($novo -join "`r`n") + "`r`n"
    $atual = if (Test-Path $hosts) { [IO.File]::ReadAllText($hosts, $ansi) } else { '' }
    if ($texto -ne $atual) {
        try {
            [IO.File]::WriteAllText($hosts, $texto, $ansi)
            ipconfig /flushdns | Out-Null
        } catch {
            Write-Host "Não foi possível atualizar o ficheiro hosts: $($_.Exception.Message)"
        }
    }
    Write-Host "Sites bloqueados: $($dominios.Count) ($($dominios -join ', ')). DNS seguro desligado no Chrome e no Edge."

    # 3) DNS automático nas placas de rede com endereço automático (DHCP),
    #    para todos os computadores usarem o filtro da rede
    $reposto = 0
    Get-NetIPInterface -AddressFamily IPv4 -Dhcp Enabled -ConnectionState Connected -ErrorAction SilentlyContinue | ForEach-Object {
        $chave = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$((Get-NetAdapter -InterfaceIndex $_.ifIndex).InterfaceGuid)"
        $manual = (Get-ItemProperty -Path $chave -Name NameServer).NameServer
        if ($manual) {
            Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses
            Write-Host "DNS manual retirado da placa $($_.InterfaceAlias) (era $manual)."
            $reposto++
        }
    }
    if ($reposto -eq 0) { Write-Host 'DNS das placas de rede: já estava automático.' }
}

# Configuração do computador para todas as contas (administrador ou SYSTEM):
# políticas dos navegadores, navegador predefinido, aplicações afixadas na
# barra de tarefas, plano de energia e Wi-Fi
function Aplicar-ConfiguracaoComputador {
    $pasta = "$env:ProgramData\LimpezaSala"
    New-Item -Path $pasta -ItemType Directory -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false

    Definir-PaginaInicialPorPolitica
    Write-Host "Página inicial do Chrome e do Edge: $PAGINA; sessão anónima obrigatória."

    # Navegador predefinido: Microsoft Edge (aplicado pelo Windows em cada início de sessão)
    $assoc = @'
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".htm" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier=".html" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier=".shtml" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier=".xht" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier=".xhtml" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier=".pdf" ProgId="MSEdgePDF" ApplicationName="Microsoft Edge" />
  <Association Identifier="http" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier="https" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier="ftp" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
</DefaultAssociations>
'@
    [IO.File]::WriteAllText("$pasta\navegador-predefinido.xml", $assoc, $utf8)
    $polSistema = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    if (-not (Test-Path $polSistema)) { New-Item -Path $polSistema -Force | Out-Null }
    Set-ItemProperty -Path $polSistema -Name DefaultAssociationsConfiguration -Value "$pasta\navegador-predefinido.xml"
    # O Chrome deixa de pedir para ser o navegador predefinido
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name DefaultBrowserSettingEnabled -Value 0 -Type DWord
    Write-Host 'Navegador predefinido: Microsoft Edge.'

    # Barra de tarefas: Explorador de Ficheiros, Edge, Chrome e Opera (se existirem)
    $menuComum = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    $pins = @('        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />',
              '        <taskbar:DesktopApp DesktopApplicationID="MSEdge" />')
    if (Test-Path "$menuComum\Google Chrome.lnk") {
        $pins += '        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk" />'
    }
    if (Test-Path "$menuComum\Opera Browser.lnk") {
        $pins += '        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Opera Browser.lnk" />'
    }
    $barra = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Limpeza da sala - gerado em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -->
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
$($pins -join "`r`n")
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
    [IO.File]::WriteAllText("$pasta\barra-de-tarefas.xml", $barra, $utf8)
    $polExplorer = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if (-not (Test-Path $polExplorer)) { New-Item -Path $polExplorer -Force | Out-Null }
    Set-ItemProperty -Path $polExplorer -Name StartLayoutFile -Value "$pasta\barra-de-tarefas.xml" -Type ExpandString
    Set-ItemProperty -Path $polExplorer -Name LockedStartLayout -Value 1 -Type DWord
    Write-Host "Barra de tarefas: $($pins.Count) aplicações afixadas por política."

    # Energia: planos de origem do Windows, com o plano Equilibrado ativo
    powercfg /restoredefaultschemes | Out-Null
    powercfg /setactive SCHEME_BALANCED | Out-Null
    Write-Host 'Energia: planos de origem repostos (Equilibrado).'

    # Roda do rato: rodar para baixo desce a página
    Repor-DirecaoRodaRato

    # Sites bloqueados, DNS seguro desligado e DNS automático
    Aplicar-SitesBloqueados

    # Ambiente de trabalho comum a todas as contas: só os atalhos dos navegadores
    $comum = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $r = Limpar-PastaAmbienteTrabalho $comum "$pasta\Retirados do ambiente de trabalho comum"
    Write-Host "Ambiente de trabalho comum: $($r.Movidos) item(ns) retirado(s), $($r.Falhados) com erro."

    Ligar-PlacasWiFi
}

# ---------------------------------------------------------------------------
# Atualização automática a partir da Internet (ou de uma pasta partilhada)
#
# Em cada arranque, a tarefa "Limpeza da sala - Rede" (SYSTEM) lê o endereço
# guardado em Endereco-Atualizacao.txt e descarrega desse endereço:
#   manifesto.txt  - versão e impressão digital (SHA-256) de cada ficheiro
#   manifesto.sig  - assinatura digital do manifesto, feita pelo professor
#                    com o Publicar-Atualizacao.bat
# Só aceita a atualização se a assinatura for válida para a chave pública
# instalada pela pen (chave-publica.txt) e se cada ficheiro descarregado
# tiver exatamente a impressão digital indicada no manifesto.
# ---------------------------------------------------------------------------
$FICHEIROS_ATUALIZAVEIS = @('Limpar-Contas-Microsoft.ps1', 'Sites-Bloqueados.txt')

function Obter-Ficheiro([string]$base, [string]$nome, [string]$destino) {
    if ($base -match '^https://') {
        $url = $base.TrimEnd('/') + '/' + $nome + '?t=' + [DateTime]::UtcNow.Ticks   # evitar cópias em cache
        Invoke-WebRequest -Uri $url -OutFile $destino -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    } elseif ($base -match '^\\\\') {
        Copy-Item -LiteralPath (Join-Path $base $nome) -Destination $destino -Force -ErrorAction Stop
    } else {
        throw "Endereço não suportado (tem de começar por https:// ou \\servidor\): $base"
    }
}

function Hash-Ficheiro([string]$caminho) {
    (Get-FileHash -LiteralPath $caminho -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Atualizar-DaInternet {
    $pasta    = "$env:ProgramData\LimpezaSala"
    $endereco = "$pasta\Endereco-Atualizacao.txt"
    $chave    = "$pasta\chave-publica.txt"
    if (-not (Test-Path $endereco) -or -not (Test-Path $chave)) {
        Write-Host 'Atualização automática: não configurada (falta o endereço ou a chave pública).'
        return $false
    }
    $base = ([IO.File]::ReadAllLines($endereco) | ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
             Where-Object { $_ } | Select-Object -First 1)
    if (-not $base) { Write-Host 'Atualização automática: endereço vazio.'; return $false }
    Write-Host "Atualização automática: a verificar $base"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $temp = "$pasta\transferencia"
    if (Test-Path $temp) { Remove-Item -Path $temp -Recurse -Force }
    New-Item -Path $temp -ItemType Directory -Force | Out-Null

    # A rede sem fios pode demorar a ligar depois do arranque: tentar durante 5 minutos
    $obtido = $false
    for ($t = 1; $t -le 20 -and -not $obtido; $t++) {
        try {
            Obter-Ficheiro $base 'manifesto.txt' "$temp\manifesto.txt"
            Obter-Ficheiro $base 'manifesto.sig' "$temp\manifesto.sig"
            $obtido = $true
        } catch {
            if ($t -eq 20) { Write-Host "Atualização automática: sem acesso ao endereço ($($_.Exception.Message))." } else { Start-Sleep -Seconds 15 }
        }
    }
    if (-not $obtido) { return $false }

    # Verificar a assinatura do manifesto com a chave pública instalada
    try {
        $p = @{}
        foreach ($l in [IO.File]::ReadAllLines($chave)) {
            if ($l -match '^\s*(Modulus|Exponent)\s*=\s*(\S+)') { $p[$matches[1]] = [Convert]::FromBase64String($matches[2]) }
        }
        $param = New-Object System.Security.Cryptography.RSAParameters
        $param.Modulus  = $p['Modulus']
        $param.Exponent = $p['Exponent']
        $csp = New-Object System.Security.Cryptography.CspParameters 24   # fornecedor com SHA-256
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider $csp
        $rsa.PersistKeyInCsp = $false
        $rsa.ImportParameters($param)
        $dados      = [IO.File]::ReadAllBytes("$temp\manifesto.txt")
        $assinatura = [Convert]::FromBase64String(([IO.File]::ReadAllText("$temp\manifesto.sig")).Trim())
        $valida = $rsa.VerifyData($dados, $assinatura,
                    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    } catch {
        $valida = $false
    }
    if (-not $valida) {
        Write-Host 'Atualização automática: ASSINATURA INVÁLIDA. Atualização recusada.' -ForegroundColor Yellow
        return $false
    }

    # Ler o manifesto
    $man = @{}
    foreach ($l in [IO.File]::ReadAllLines("$temp\manifesto.txt")) {
        if ($l -match '^\s*([^=#]+?)\s*=\s*(\S+)\s*$') { $man[$matches[1]] = $matches[2] }
    }
    Write-Host "Atualização automática: manifesto válido, versão $($man['versao']) (instalada: $VERSAO)."

    # Descarregar e confirmar cada ficheiro; só substituir os que mudaram
    $mudou = $false
    foreach ($nome in $FICHEIROS_ATUALIZAVEIS) {
        if (-not $man.ContainsKey($nome)) { continue }
        $esperado = $man[$nome].ToLowerInvariant()
        $local = Join-Path $pasta $nome
        if ((Test-Path $local) -and (Hash-Ficheiro $local) -eq $esperado) { continue }
        try {
            Obter-Ficheiro $base $nome "$temp\$nome"
        } catch {
            Write-Host "Atualização automática: não foi possível descarregar $nome ($($_.Exception.Message))."
            continue
        }
        if ((Hash-Ficheiro "$temp\$nome") -ne $esperado) {
            Write-Host "Atualização automática: $nome não corresponde ao manifesto. Recusado." -ForegroundColor Yellow
            continue
        }
        Copy-Item -LiteralPath "$temp\$nome" -Destination $local -Force
        Write-Host "Atualização automática: $nome atualizado."
        $mudou = $true
    }
    Remove-Item -Path $temp -Recurse -Force
    if (-not $mudou) { Write-Host 'Atualização automática: os ficheiros já estavam atualizados.' }
    return $mudou
}

if ($Sistema) {
    $pastaSistema = "$env:ProgramData\LimpezaSala"
    New-Item -Path $pastaSistema -ItemType Directory -Force | Out-Null
    # Quando é a versão nova a continuar o arranque, acrescenta ao mesmo registo
    if ($SemAtualizar) { Start-Transcript -Path "$pastaSistema\registo-sistema.txt" -Append | Out-Null } else { Start-Transcript -Path "$pastaSistema\registo-sistema.txt" -Force | Out-Null }
    Write-Host "Arranque do computador: $(Get-Date -Format 'dd/MM/yyyy HH:mm') - versão $VERSAO"
    if (-not $SemAtualizar) {
        Ligar-PlacasWiFi                         # a atualização precisa de rede
        if (Atualizar-DaInternet) {
            # Há uma versão nova: é ela que aplica a configuração deste arranque
            Write-Host 'A aplicar a configuração com a versão nova...'
            Stop-Transcript | Out-Null
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$pastaSistema\Limpar-Contas-Microsoft.ps1" -Sistema -SemAtualizar
            exit 0
        }
    }
    Aplicar-ConfiguracaoComputador
    Stop-Transcript | Out-Null
    exit 0
}

if ($Administracao) {
    if (-not $eAdministrador) {
        Write-Host 'O modo de administração tem de ser executado como administrador.' -ForegroundColor Yellow
        exit 1
    }
    Aplicar-ConfiguracaoComputador
    exit 0
}

if ($Automatico) {
    $pastaRegisto = "$env:LOCALAPPDATA\LimpezaSala"
    New-Item -Path $pastaRegisto -ItemType Directory -Force | Out-Null
    Start-Transcript -Path "$pastaRegisto\ultimo-registo.txt" -Force | Out-Null
    Start-Sleep -Seconds 5   # dar tempo ao Windows para acabar de abrir a sessão
}

function Escrever($texto, $cor = 'White') { Write-Host $texto -ForegroundColor $cor }

# Funções do Windows usadas para aplicar as definições sem reiniciar
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WinAPI {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(uint acao, uint uiParam, string pvParam, uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint acao, uint uiParam, int[] pvParam, uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint acao, uint uiParam, IntPtr pvParam, uint flags);
}
'@

# Funções do Windows para o som
Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class Som {
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams,
                                   [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float levelDB, ref Guid context);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid context);
        [PreserveSig] int GetMasterVolumeLevel(out float levelDB);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float levelDB, ref Guid context);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float levelDB);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    // Põe o som em silêncio, com o volume a meio (para quando for ligado).
    public static string Silenciar(float volume) {
        try {
            Type t = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
            IMMDeviceEnumerator en = (IMMDeviceEnumerator)Activator.CreateInstance(t);
            IMMDevice dev;
            if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null)   // eRender, eMultimedia
                return "Não existe saída de som ativa.";
            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object o;
            if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0 || o == null)  // CLSCTX_ALL
                return "Não foi possível aceder ao controlo de volume.";
            IAudioEndpointVolume vol = (IAudioEndpointVolume)o;
            Guid ctx = Guid.Empty;
            vol.SetMasterVolumeLevelScalar(volume, ref ctx);
            vol.SetMute(true, ref ctx);
            bool mudo; vol.GetMute(out mudo);
            return mudo ? "Som em silêncio (volume a " + (int)(volume * 100) + "% quando for ligado)."
                        : "Não foi possível pôr o som em silêncio.";
        } catch (Exception e) {
            return "Não foi possível alterar o som: " + e.Message;
        }
    }
}
'@

# Funções do Windows para o tema, o idioma e as teclas de acessibilidade
Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class Definicoes {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
                                            uint flags, uint timeout, out UIntPtr result);

    // Avisa todas as janelas de que uma definição mudou (ex.: "ImmersiveColorSet"
    // para o tema claro/escuro, "intl" para o idioma, null para as gerais)
    public static void Avisar(string area) {
        UIntPtr r;
        SendMessageTimeout((IntPtr)0xFFFF, 0x001A, UIntPtr.Zero, area, 0x0002, 3000, out r);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct STICKYKEYS { public uint cbSize; public uint dwFlags; }

    [StructLayout(LayoutKind.Sequential)]
    struct TOGGLEKEYS { public uint cbSize; public uint dwFlags; }

    [StructLayout(LayoutKind.Sequential)]
    struct FILTERKEYS {
        public uint cbSize; public uint dwFlags;
        public uint iWaitMSec; public uint iDelayMSec; public uint iRepeatMSec; public uint iBounceMSec;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEKEYS {
        public uint cbSize; public uint dwFlags; public uint iMaxSpeed; public uint iTimeToMaxSpeed;
        public uint iCtrlSpeed; public uint dwReserved1; public uint dwReserved2;
    }

    [DllImport("user32.dll", SetLastError = true)] static extern bool SystemParametersInfo(uint a, uint u, ref STICKYKEYS p, uint f);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SystemParametersInfo(uint a, uint u, ref TOGGLEKEYS p, uint f);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SystemParametersInfo(uint a, uint u, ref FILTERKEYS p, uint f);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SystemParametersInfo(uint a, uint u, ref MOUSEKEYS p, uint f);

    // Repõe as Teclas Presas, Teclas de Filtro, Teclas de Alternância e
    // Teclas do Rato nos valores de origem do Windows (todas desligadas,
    // com os atalhos de teclado disponíveis).
    public static void ReporTeclasAcessibilidade() {
        STICKYKEYS sk = new STICKYKEYS();
        sk.cbSize = (uint)Marshal.SizeOf(typeof(STICKYKEYS)); sk.dwFlags = 510;
        SystemParametersInfo(0x003B, sk.cbSize, ref sk, 3);          // SPI_SETSTICKYKEYS

        TOGGLEKEYS tk = new TOGGLEKEYS();
        tk.cbSize = (uint)Marshal.SizeOf(typeof(TOGGLEKEYS)); tk.dwFlags = 62;
        SystemParametersInfo(0x0035, tk.cbSize, ref tk, 3);          // SPI_SETTOGGLEKEYS

        FILTERKEYS fk = new FILTERKEYS();
        fk.cbSize = (uint)Marshal.SizeOf(typeof(FILTERKEYS)); fk.dwFlags = 126;
        fk.iWaitMSec = 1000; fk.iDelayMSec = 1000; fk.iRepeatMSec = 500; fk.iBounceMSec = 0;
        SystemParametersInfo(0x0033, fk.cbSize, ref fk, 3);          // SPI_SETFILTERKEYS

        MOUSEKEYS mk = new MOUSEKEYS();
        mk.cbSize = (uint)Marshal.SizeOf(typeof(MOUSEKEYS)); mk.dwFlags = 62;
        mk.iMaxSpeed = 80; mk.iTimeToMaxSpeed = 3000;
        SystemParametersInfo(0x0037, mk.cbSize, ref mk, 3);          // SPI_SETMOUSEKEYS
    }
}
'@

# Funções do Windows para o fundo e o tamanho dos ícones do ambiente de trabalho
Add-Type @'
using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;

public static class AmbTrab {

    // ------------------------------------------------------------------
    // Fundo do ambiente de trabalho (IDesktopWallpaper, Windows 8 ou superior)
    // ------------------------------------------------------------------
    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDesktopWallpaper {
        [PreserveSig] int SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [PreserveSig] int GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] out string wallpaper);
        [PreserveSig] int GetMonitorDevicePathAt(uint monitorIndex, [MarshalAs(UnmanagedType.LPWStr)] out string monitorID);
        [PreserveSig] int GetMonitorDevicePathCount(out uint count);
        [PreserveSig] int GetMonitorRECT_(); // não usado
        [PreserveSig] int SetBackgroundColor(uint color);
        [PreserveSig] int GetBackgroundColor(out uint color);
        [PreserveSig] int SetPosition(int position);
        [PreserveSig] int GetPosition(out int position);
        [PreserveSig] int SetSlideshow(IntPtr items);
        [PreserveSig] int GetSlideshow(out IntPtr items);
        [PreserveSig] int SetSlideshowOptions(int options, uint slideshowTick);
        [PreserveSig] int GetSlideshowOptions(out int options, out uint slideshowTick);
        [PreserveSig] int AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorID, int direction);
        [PreserveSig] int GetStatus(out int state);
        [PreserveSig] int Enable([MarshalAs(UnmanagedType.Bool)] bool enable);
    }

    const int DWPOS_FILL = 4;

    // Aplica a imagem em todos os monitores, em modo "Preencher".
    // Devolve uma descrição do resultado, monitor a monitor.
    public static string DefinirFundo(string imagem) {
        try {
            Type t = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD"));
            IDesktopWallpaper dw = (IDesktopWallpaper)Activator.CreateInstance(t);
            dw.Enable(true);
            int r1 = dw.SetWallpaper(null, imagem);
            int r2 = dw.SetPosition(DWPOS_FILL);
            uint n; dw.GetMonitorDevicePathCount(out n);
            int certos = 0;
            for (uint i = 0; i < n; i++) {
                string id, atual;
                if (dw.GetMonitorDevicePathAt(i, out id) == 0 && dw.GetWallpaper(id, out atual) == 0
                    && string.Equals(atual, imagem, StringComparison.OrdinalIgnoreCase)) certos++;
            }
            Marshal.ReleaseComObject(dw);
            return "IDesktopWallpaper: SetWallpaper=" + r1 + ", SetPosition=" + r2 + ", monitores com o fundo certo: " + certos + " de " + n;
        } catch (Exception e) {
            return "IDesktopWallpaper indisponível: " + e.Message;
        }
    }

    // ------------------------------------------------------------------
    // Tamanho dos ícones do ambiente de trabalho (IFolderView2 da vista
    // do ambiente de trabalho, o mesmo que o Ctrl+roda do rato altera)
    // ------------------------------------------------------------------
    [ComImport, Guid("6D5140C1-7436-11CE-8034-00AA006009FA"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IServiceProvider {
        [PreserveSig] int QueryService(ref Guid guidService, ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppvObject);
    }

    [ComImport, Guid("000214E2-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellBrowser {
        [PreserveSig] int GetWindow(out IntPtr hwnd);
        [PreserveSig] int ContextSensitiveHelp(int enter);
        [PreserveSig] int InsertMenusSB(IntPtr a, IntPtr b);
        [PreserveSig] int SetMenuSB(IntPtr a, IntPtr b, IntPtr c);
        [PreserveSig] int RemoveMenusSB(IntPtr a);
        [PreserveSig] int SetStatusTextSB(IntPtr a);
        [PreserveSig] int EnableModelessSB(int a);
        [PreserveSig] int TranslateAcceleratorSB(IntPtr a, short b);
        [PreserveSig] int BrowseObject(IntPtr a, uint b);
        [PreserveSig] int GetViewStateStream(uint a, out IntPtr b);
        [PreserveSig] int GetControlWindow(uint a, out IntPtr b);
        [PreserveSig] int SendControlMsg(uint a, uint b, IntPtr c, IntPtr d, out IntPtr e);
        [PreserveSig] int QueryActiveShellView([MarshalAs(UnmanagedType.IUnknown)] out object ppshv);
    }

    [ComImport, Guid("1af3a467-214f-4298-908e-06b03e0b39f9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFolderView2 {
        // IFolderView
        [PreserveSig] int GetCurrentViewMode(out uint mode);
        [PreserveSig] int SetCurrentViewMode(uint mode);
        [PreserveSig] int GetFolder(ref Guid riid, out IntPtr ppv);
        [PreserveSig] int Item(int index, out IntPtr ppidl);
        [PreserveSig] int ItemCount(uint flags, out int count);
        [PreserveSig] int Items(uint flags, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int GetSelectionMarkedItem(out int item);
        [PreserveSig] int GetFocusedItem(out int item);
        [PreserveSig] int GetItemPosition(IntPtr pidl, out long pt);
        [PreserveSig] int GetSpacing(out long pt);
        [PreserveSig] int GetDefaultSpacing(out long pt);
        [PreserveSig] int GetAutoArrange();
        [PreserveSig] int SelectItem(int item, uint flags);
        [PreserveSig] int SelectAndPositionItems(uint cidl, IntPtr apidl, IntPtr apt, uint flags);
        // IFolderView2
        [PreserveSig] int SetGroupBy(IntPtr key, int ascending);
        [PreserveSig] int GetGroupBy(IntPtr key, out int ascending);
        [PreserveSig] int SetViewProperty(IntPtr pidl, IntPtr key, IntPtr value);
        [PreserveSig] int GetViewProperty(IntPtr pidl, IntPtr key, IntPtr value);
        [PreserveSig] int SetTileViewProperties(IntPtr pidl, IntPtr props);
        [PreserveSig] int SetExtendedTileViewProperties(IntPtr pidl, IntPtr props);
        [PreserveSig] int SetText(int type, IntPtr text);
        [PreserveSig] int SetCurrentFolderFlags(uint mask, uint flags);
        [PreserveSig] int GetCurrentFolderFlags(out uint flags);
        [PreserveSig] int GetSortColumnCount(out int count);
        [PreserveSig] int SetSortColumns(IntPtr cols, int count);
        [PreserveSig] int GetSortColumns(IntPtr cols, int count);
        [PreserveSig] int GetItem(int item, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int GetVisibleItem(int start, int previous, out int item);
        [PreserveSig] int GetSelectedItem(int start, out int item);
        [PreserveSig] int GetSelection(int noneImpliesFolder, out IntPtr ppsia);
        [PreserveSig] int GetSelectionState(IntPtr pidl, out uint flags);
        [PreserveSig] int InvokeVerbOnSelection(IntPtr verb);
        [PreserveSig] int SetViewModeAndIconSize(int mode, int imageSize);
        [PreserveSig] int GetViewModeAndIconSize(out int mode, out int imageSize);
    }

    const int CSIDL_DESKTOP = 0;
    const int SWC_DESKTOP = 8;
    const int SWFO_NEEDDISPATCH = 1;
    const int FVM_ICON = 1;

    static IFolderView2 VistaDoAmbienteDeTrabalho() {
        Type t = Type.GetTypeFromCLSID(new Guid("9BA05972-F6A8-11CF-A442-00A0C90A8F39"));   // ShellWindows
        object janelas = Activator.CreateInstance(t);
        object[] args = new object[] { CSIDL_DESKTOP, null, SWC_DESKTOP, 0, SWFO_NEEDDISPATCH };
        ParameterModifier pm = new ParameterModifier(5);
        pm[3] = true;
        object disp = t.InvokeMember("FindWindowSW", BindingFlags.InvokeMethod, null, janelas,
                                     args, new ParameterModifier[] { pm }, null, null);
        if (disp == null) return null;
        Guid sid = new Guid("4C96BE40-915C-11CF-99D3-00AA004AE837");   // SID_STopLevelBrowser
        Guid iid = typeof(IShellBrowser).GUID;
        object obj;
        if (((IServiceProvider)disp).QueryService(ref sid, ref iid, out obj) != 0 || obj == null) return null;
        object vista;
        if (((IShellBrowser)obj).QueryActiveShellView(out vista) != 0 || vista == null) return null;
        return (IFolderView2)vista;
    }

    // Espera até 'segundos' que o ambiente de trabalho esteja pronto e
    // aplica a vista "Ícones" com o tamanho indicado (48 = ícones médios).
    public static string DefinirTamanhoIcones(int tamanho, int segundos) {
        string ultimoErro = "ambiente de trabalho não encontrado";
        for (int s = 0; s < segundos; s++) {
            try {
                IFolderView2 fv = VistaDoAmbienteDeTrabalho();
                if (fv != null) {
                    int modo, atual;
                    fv.GetViewModeAndIconSize(out modo, out atual);
                    if (modo == FVM_ICON && atual == tamanho)
                        return "Os ícones já estavam no tamanho " + tamanho + ".";
                    int r = fv.SetViewModeAndIconSize(FVM_ICON, tamanho);
                    int novoModo, novo;
                    fv.GetViewModeAndIconSize(out novoModo, out novo);
                    return "Tamanho dos ícones: " + atual + " -> " + novo + " (resultado " + r + ").";
                }
            } catch (Exception e) {
                ultimoErro = e.Message;
            }
            Thread.Sleep(1000);
        }
        return "Não foi possível alterar o tamanho dos ícones: " + ultimoErro;
    }
}
'@

# Funções do Windows para repor resolução, orientação, escala e contraste
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Ecra {
    // ------------------------------------------------------------------
    // Resolução e orientação
    // ------------------------------------------------------------------
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, uint flags, IntPtr lParam);

    const int ENUM_CURRENT_SETTINGS = -1;
    const int ATTACHED_TO_DESKTOP = 0x1;
    const int DM_DISPLAYORIENTATION = 0x80;
    const int DM_PELSWIDTH = 0x80000;
    const int DM_PELSHEIGHT = 0x100000;
    const int DM_DISPLAYFREQUENCY = 0x400000;
    const uint CDS_UPDATEREGISTRY = 0x1;

    static DEVMODE NovoDevMode() {
        DEVMODE dm = new DEVMODE();
        dm.dmDeviceName = new string('\0', 32);
        dm.dmFormName = new string('\0', 32);
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        return dm;
    }

    // Repõe cada ecrã na resolução máxima suportada (a nativa nos ecrãs
    // planos), em orientação horizontal, preferindo 60 Hz.
    public static string[] ReporResolucao() {
        List<string> registo = new List<string>();
        DISPLAY_DEVICE dd = new DISPLAY_DEVICE();
        dd.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
        for (uint i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++) {
            if ((dd.StateFlags & ATTACHED_TO_DESKTOP) != 0) {
                string nome = dd.DeviceName;
                DEVMODE atual = NovoDevMode();
                if (EnumDisplaySettings(nome, ENUM_CURRENT_SETTINGS, ref atual)) {
                    int melhorL = 0, melhorA = 0;
                    List<int> frequencias = new List<int>();
                    DEVMODE m = NovoDevMode();
                    for (int n = 0; EnumDisplaySettings(nome, n, ref m); n++) {
                        if (m.dmBitsPerPel < 32) continue;
                        int l = Math.Max(m.dmPelsWidth, m.dmPelsHeight);
                        int a = Math.Min(m.dmPelsWidth, m.dmPelsHeight);
                        if ((long)l * a > (long)melhorL * melhorA) {
                            melhorL = l; melhorA = a; frequencias.Clear();
                        }
                        if (l == melhorL && a == melhorA && !frequencias.Contains(m.dmDisplayFrequency))
                            frequencias.Add(m.dmDisplayFrequency);
                        m = NovoDevMode();
                    }
                    if (melhorL > 0) {
                        int freq = frequencias.Contains(60) ? 60 : (frequencias.Count > 0 ? frequencias[0] : atual.dmDisplayFrequency);
                        bool igual = atual.dmPelsWidth == melhorL && atual.dmPelsHeight == melhorA
                                     && atual.dmDisplayOrientation == 0;
                        if (igual) {
                            registo.Add(nome + ": já estava em " + melhorL + "x" + melhorA + ", horizontal.");
                        } else {
                            DEVMODE novo = atual;
                            novo.dmPelsWidth = melhorL;
                            novo.dmPelsHeight = melhorA;
                            novo.dmDisplayOrientation = 0;
                            novo.dmDisplayFrequency = freq;
                            novo.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYORIENTATION | DM_DISPLAYFREQUENCY;
                            int r = ChangeDisplaySettingsEx(nome, ref novo, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
                            registo.Add(nome + ": " + (r == 0 ? "reposto para " : "não foi possível repor ") + melhorL + "x" + melhorA + " (código " + r + ").");
                        }
                    }
                }
            }
            dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
        }
        return registo.ToArray();
    }

    // ------------------------------------------------------------------
    // Escala (o "zoom" do Windows): repõe o valor recomendado
    // ------------------------------------------------------------------
    [StructLayout(LayoutKind.Sequential)]
    struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    struct DPI_GET {
        public int type; public int size; public LUID adapterId; public uint id;
        public int minScaleRel; public int curScaleRel; public int maxScaleRel;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct DPI_SET {
        public int type; public int size; public LUID adapterId; public uint id;
        public int scaleRel;
    }

    [DllImport("user32.dll")]
    static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
    [DllImport("user32.dll")]
    static extern int QueryDisplayConfig(uint flags, ref uint numPaths, byte[] paths, ref uint numModes, byte[] modes, IntPtr topology);
    [DllImport("user32.dll")]
    static extern int DisplayConfigGetDeviceInfo(ref DPI_GET info);
    [DllImport("user32.dll")]
    static extern int DisplayConfigSetDeviceInfo(ref DPI_SET info);

    const uint QDC_ONLY_ACTIVE_PATHS = 0x2;
    const int TAMANHO_CAMINHO = 72;
    const int TAMANHO_MODO = 64;

    public static string[] ReporEscala() {
        List<string> registo = new List<string>();
        uint nCaminhos, nModos;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out nCaminhos, out nModos) != 0) {
            registo.Add("Não foi possível ler a configuração dos ecrãs.");
            return registo.ToArray();
        }
        byte[] caminhos = new byte[nCaminhos * TAMANHO_CAMINHO];
        byte[] modos = new byte[nModos * TAMANHO_MODO];
        if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref nCaminhos, caminhos, ref nModos, modos, IntPtr.Zero) != 0) {
            registo.Add("Não foi possível ler a configuração dos ecrãs.");
            return registo.ToArray();
        }
        for (int i = 0; i < nCaminhos; i++) {
            int o = i * TAMANHO_CAMINHO;
            LUID adaptador = new LUID();
            adaptador.LowPart = BitConverter.ToUInt32(caminhos, o);
            adaptador.HighPart = BitConverter.ToInt32(caminhos, o + 4);
            uint origem = BitConverter.ToUInt32(caminhos, o + 8);

            DPI_GET g = new DPI_GET();
            g.type = -3; g.size = Marshal.SizeOf(typeof(DPI_GET));
            g.adapterId = adaptador; g.id = origem;
            if (DisplayConfigGetDeviceInfo(ref g) == 0 && g.curScaleRel == 0) {
                registo.Add("Ecrã " + (i + 1) + ": a escala já estava no valor recomendado.");
                continue;
            }

            DPI_SET s = new DPI_SET();
            s.type = -4; s.size = Marshal.SizeOf(typeof(DPI_SET));
            s.adapterId = adaptador; s.id = origem; s.scaleRel = 0;
            int r = DisplayConfigSetDeviceInfo(ref s);
            registo.Add("Ecrã " + (i + 1) + ": " + (r == 0 ? "escala reposta no valor recomendado." : "não foi possível repor a escala (código " + r + ")."));
        }
        return registo.ToArray();
    }

    // ------------------------------------------------------------------
    // Alto contraste
    // ------------------------------------------------------------------
    [StructLayout(LayoutKind.Sequential)]
    struct HIGHCONTRAST { public int cbSize; public uint dwFlags; public IntPtr lpszDefaultScheme; }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool SystemParametersInfo(uint acao, uint uiParam, ref HIGHCONTRAST pv, uint flags);

    public static bool DesligarAltoContraste() {
        HIGHCONTRAST hc = new HIGHCONTRAST();
        hc.cbSize = Marshal.SizeOf(typeof(HIGHCONTRAST));
        if (!SystemParametersInfo(0x0042, (uint)hc.cbSize, ref hc, 0)) return false;   // SPI_GETHIGHCONTRAST
        if ((hc.dwFlags & 0x1) == 0) return false;                                      // já desligado
        hc.dwFlags &= ~0x1u;
        hc.lpszDefaultScheme = IntPtr.Zero;
        return SystemParametersInfo(0x0043, (uint)hc.cbSize, ref hc, 3);                // SPI_SETHIGHCONTRAST
    }
}
'@

$GRAVAR = 3   # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE

if (-not $Automatico) { Clear-Host }
Escrever '=================================================================' Cyan
Escrever '  Limpeza de contas Microsoft 365 e reposição das definições' Cyan
Escrever '=================================================================' Cyan
Escrever ''
Escrever "Utilizador do Windows: $env:USERNAME" Yellow
Escrever "Versão do script: $VERSAO (31/10/2026)" Yellow
Escrever "Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')" Yellow
Escrever ''
if (-not $Automatico) {
    Escrever 'Este script vai fechar o Teams, o Outlook, o Word, o Excel, o'
    Escrever 'PowerPoint, o OneDrive, o Edge e o Chrome, e apagar as contas'
    Escrever 'guardadas. Nos navegadores, a sessão termina em todos os sites.'
    Escrever 'Vai também repor o fundo do ambiente de trabalho, o rato, o'
    Escrever 'os ícones e as definições de visualização (resolução,'
    Escrever 'escala, texto e zoom). O ecrã pode piscar por instantes.'
    Escrever 'Os ficheiros e atalhos deixados no ambiente de trabalho são'
    Escrever 'retirados para a pasta LimpezaSala (guardados durante 14 dias).'
    Escrever 'Guarde qualquer trabalho aberto antes de continuar.'
    Escrever ''
    $resposta = if ($Confirmado) { 'S' } else { Read-Host 'Pretende continuar? (S/N)' }
    if ($resposta -notmatch '^[sS]') {
        Escrever 'Operação cancelada.' Yellow
        Start-Sleep -Seconds 2
        exit
    }
}

# ---------------------------------------------------------------------------
# 1. Fechar aplicações que usam as contas
# ---------------------------------------------------------------------------
Escrever ''
Escrever '[1/17] A fechar aplicações...' Cyan
$processos = 'ms-teams','Teams','msedgewebview2','OUTLOOK','WINWORD','EXCEL',
             'POWERPNT','ONENOTE','OneDrive','msedge','chrome','opera',
             'Microsoft.AAD.BrokerPlugin'
foreach ($p in $processos) { Get-Process -Name $p | Stop-Process -Force }
Start-Sleep -Seconds 3

# ---------------------------------------------------------------------------
# 2. Apagar credenciais do Gestor de Credenciais do Windows
# ---------------------------------------------------------------------------
Escrever '[2/17] A apagar credenciais guardadas no Gestor de Credenciais...' Cyan
$padroes = 'MicrosoftOffice','msteams','Teams','OneAuth','MicrosoftAccount',
           'OneDrive','microsoftonline','ADAL','Outlook'
$listagem = cmdkey /list
$apagadas = 0
foreach ($linha in $listagem) {
    $alvo = $null
    if ($linha -match '(?i)target=(.+)$')          { $alvo = $matches[1].Trim() }
    elseif ($linha -match '^\s*[^:]+:\s*(\S+)\s*$') { $alvo = $matches[1].Trim() }
    if (-not $alvo) { continue }
    foreach ($pd in $padroes) {
        if ($alvo -like "*$pd*") {
            cmdkey /delete:"$alvo" | Out-Null
            $apagadas++
            break
        }
    }
}
Escrever "      Credenciais removidas: $apagadas"

# ---------------------------------------------------------------------------
# 3. Apagar caches de autenticação (OneAuth, IdentityCache, TokenBroker)
# ---------------------------------------------------------------------------
Escrever '[3/17] A apagar caches de autenticação...' Cyan
$pastas = @(
    "$env:LOCALAPPDATA\Microsoft\OneAuth",
    "$env:LOCALAPPDATA\Microsoft\IdentityCache",
    "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache",
    "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Accounts",
    "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Cache",
    "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\Settings"
)
foreach ($pasta in $pastas) {
    if (Test-Path $pasta) {
        Remove-Item -Path $pasta -Recurse -Force
        Escrever "      Removido: $pasta" DarkGray
    }
}

# ---------------------------------------------------------------------------
# 4. Apagar identidades guardadas pelo Office
# ---------------------------------------------------------------------------
Escrever '[4/17] A apagar identidades do Office...' Cyan
$chaves = @(
    'HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Identities',
    'HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Profiles',
    'HKCU:\Software\Microsoft\Office\16.0\Common\Identity\DeviceId',
    'HKCU:\Software\Microsoft\Office\16.0\Common\Roaming\Identities',
    'HKCU:\Software\Microsoft\Office\16.0\Common\ServicesManagerCache\Identities'
)
foreach ($ch in $chaves) {
    if (Test-Path $ch) { Remove-Item -Path $ch -Recurse -Force }
}

# ---------------------------------------------------------------------------
# 5. Apagar sessão guardada do Teams (novo e clássico)
# ---------------------------------------------------------------------------
Escrever '[5/17] A apagar a sessão guardada do Teams...' Cyan
$pastasTeams = @(
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache",
    "$env:APPDATA\Microsoft\Teams"
)
foreach ($pasta in $pastasTeams) {
    if (Test-Path $pasta) {
        Remove-Item -Path $pasta -Recurse -Force
        Escrever "      Removido: $pasta" DarkGray
    }
}

# ---------------------------------------------------------------------------
# 6. Apagar cookies e sessões do Google Chrome e do Microsoft Edge
#    (mantém marcadores, histórico e palavras-passe guardadas)
# ---------------------------------------------------------------------------
Escrever '[6/17] A apagar sessões iniciadas no Chrome, no Edge e no Opera...' Cyan
$navegadores = @{
    'Google Chrome'  = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    'Microsoft Edge' = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    'Opera'          = "$env:APPDATA\Opera Software\Opera Stable"
    'Opera GX'       = "$env:APPDATA\Opera Software\Opera GX Stable"
}
$itensSessao = @(
    'Network\Cookies', 'Network\Cookies-journal',
    'Cookies', 'Cookies-journal',
    'Sessions', 'Current Session', 'Current Tabs', 'Last Session', 'Last Tabs',
    'Local Storage', 'Session Storage', 'IndexedDB', 'Service Worker'
)
foreach ($nome in $navegadores.Keys) {
    $base = $navegadores[$nome]
    if (-not (Test-Path $base)) { continue }
    $perfis = @(Get-ChildItem -Path $base -Directory |
              Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
    # O Opera guarda o perfil principal diretamente na pasta base
    if (Test-Path (Join-Path $base 'Preferences')) { $perfis += Get-Item -LiteralPath $base }
    foreach ($perfil in $perfis) {
        foreach ($item in $itensSessao) {
            $caminho = Join-Path $perfil.FullName $item
            if (Test-Path $caminho) { Remove-Item -Path $caminho -Recurse -Force }
        }
    }
    Escrever "      $nome`: $(@($perfis).Count) perfil(is) limpo(s)" DarkGray
}

# ---------------------------------------------------------------------------
# 7. Repor o tema claro e o fundo do ambiente de trabalho original
# ---------------------------------------------------------------------------
Escrever '[7/17] A repor o tema claro e o fundo do ambiente de trabalho...' Cyan

# Tema claro do Windows, com a cor de destaque e a transparência de origem
$pers     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$temas    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes'
$temaClaro = "$env:WINDIR\resources\Themes\aero.theme"     # "Windows (claro)"
if (-not (Test-Path $pers)) { New-Item -Path $pers -Force | Out-Null }
$p = Get-ItemProperty -Path $pers
$temaAtual = (Get-ItemProperty -Path $temas -Name CurrentTheme).CurrentTheme
$estavaEscuro = ($p.AppsUseLightTheme -ne 1 -or $p.SystemUsesLightTheme -ne 1)
Escrever "      Antes: aplicações=$($p.AppsUseLightTheme), sistema=$($p.SystemUsesLightTheme), tema=$temaAtual" DarkGray

# Se o tema estava escuro ou era outro, aplicar o tema "Windows (claro)"
# pelo próprio Windows (é a única forma de o Windows o guardar como tema
# ativo e não voltar ao escuro no arranque seguinte)
if ($estavaEscuro -or ($temaAtual -notlike '*\aero.theme')) {
    # Apagar o tema personalizado guardado pelo aluno
    Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\Themes\Custom.theme" -Force
    if (Test-Path $temaClaro) {
        Start-Process -FilePath $temaClaro
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 1
            $q = Get-ItemProperty -Path $pers
            if ($q.AppsUseLightTheme -eq 1 -and $q.SystemUsesLightTheme -eq 1) { break }
        }
        Start-Sleep -Seconds 2
        Get-Process -Name SystemSettings | Stop-Process -Force   # fechar as Definições
        Escrever '      Tema "Windows (claro)" aplicado pelo Windows.' DarkGray
    } else {
        Escrever "      Não foi encontrado o tema $temaClaro." Yellow
    }
}

# Garantir os valores de origem do tema claro
Set-ItemProperty -Path $pers -Name AppsUseLightTheme    -Value 1 -Type DWord
Set-ItemProperty -Path $pers -Name SystemUsesLightTheme -Value 1 -Type DWord
Set-ItemProperty -Path $pers -Name EnableTransparency   -Value 1 -Type DWord
Set-ItemProperty -Path $pers -Name ColorPrevalence      -Value 0 -Type DWord
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name ColorPrevalence -Value 0 -Type DWord
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name AutoColorization -Value 0 -Type DWord
if ($estavaEscuro) { Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Recurse -Force }
Set-ItemProperty -Path $temas -Name CurrentTheme -Value $temaClaro
[Definicoes]::Avisar('ImmersiveColorSet')
if ($estavaEscuro) { $reiniciarExploradorTema = $true }   # a barra de tarefas só muda de cor ao reiniciar o Explorador
$p = Get-ItemProperty -Path $pers
Escrever "      Depois: aplicações=$($p.AppsUseLightTheme), sistema=$($p.SystemUsesLightTheme). Tema claro aplicado." DarkGray

$fundoOriginal = $null
$politica = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name Wallpaper
if ($politica.Wallpaper) {
    Escrever '      O fundo é imposto pela escola (política). Não foi alterado.' Yellow
} else {
    # Imagem original do Windows 11 para o tema claro (sempre a mesma)
    $imagem = "$env:WINDIR\Web\Wallpaper\Windows\img0.jpg"
    if (Test-Path $imagem) {
        # Tipo de fundo "Imagem" (desliga o Windows Spotlight e a apresentação)
        $chaveFundo = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
        if (-not (Test-Path $chaveFundo)) { New-Item -Path $chaveFundo -Force | Out-Null }
        Set-ItemProperty -Path $chaveFundo -Name BackgroundType -Value 0 -Type DWord
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DesktopSpotlight\Settings' -Name EnabledState -Value 0 -Type DWord

        # Ajuste "Preencher", sem mosaico
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value '0'
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper      -Value $imagem

        # Desligar a apresentação de diapositivos, se existir
        Set-ItemProperty -Path $chaveFundo -Name SlideshowEnabled -Value 0 -Type DWord

        [WinAPI]::SystemParametersInfo(0x0014, 0, $imagem, $GRAVAR) | Out-Null   # SPI_SETDESKWALLPAPER
        $fundoOriginal = $imagem   # volta a ser aplicado no passo 11, com o ambiente de trabalho pronto
        Escrever "      Fundo definido: $imagem" DarkGray
    } else {
        Escrever '      Não foi encontrada a imagem original do Windows.' Yellow
    }
}

# ---------------------------------------------------------------------------
# 8. Repor as definições do rato e os ponteiros originais
# ---------------------------------------------------------------------------
Escrever '[8/17] A repor as definições do rato...' Cyan
$rato = 'HKCU:\Control Panel\Mouse'
$valoresRato = @{
    MouseSpeed          = '1'     # Melhorar precisão do ponteiro: ligado
    MouseThreshold1     = '6'
    MouseThreshold2     = '10'
    MouseSensitivity    = '10'    # Velocidade do ponteiro: meio da escala
    SwapMouseButtons    = '0'     # Botão principal: esquerdo
    DoubleClickSpeed    = '500'   # Velocidade do duplo clique
    DoubleClickWidth    = '4'
    DoubleClickHeight   = '4'
    MouseTrails         = '0'     # Rasto do ponteiro: desligado
    SnapToDefaultButton = '0'
    MouseHoverTime      = '400'
}
foreach ($v in $valoresRato.Keys) { Set-ItemProperty -Path $rato -Name $v -Value $valoresRato[$v] }

# Roda do rato: 3 linhas na vertical e 3 carateres na horizontal
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WheelScrollLines -Value '3'
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WheelScrollChars -Value '3'

# Ponteiros: esquema "Predefinição do Windows", tamanho e cor normais
$cursores = 'HKCU:\Control Panel\Cursors'
$esquema = [ordered]@{
    '(Default)'   = 'Windows Default'
    AppStarting   = '%SystemRoot%\cursors\aero_working.ani'
    Arrow         = '%SystemRoot%\cursors\aero_arrow.cur'
    Crosshair     = ''
    Hand          = '%SystemRoot%\cursors\aero_link.cur'
    Help          = '%SystemRoot%\cursors\aero_helpsel.cur'
    IBeam         = ''
    No            = '%SystemRoot%\cursors\aero_unavail.cur'
    NWPen         = '%SystemRoot%\cursors\aero_pen.cur'
    Person        = '%SystemRoot%\cursors\aero_person.cur'
    Pin           = '%SystemRoot%\cursors\aero_pin.cur'
    SizeAll       = '%SystemRoot%\cursors\aero_move.cur'
    SizeNESW      = '%SystemRoot%\cursors\aero_nesw.cur'
    SizeNS        = '%SystemRoot%\cursors\aero_ns.cur'
    SizeNWSE      = '%SystemRoot%\cursors\aero_nwse.cur'
    SizeWE        = '%SystemRoot%\cursors\aero_ew.cur'
    UpArrow       = '%SystemRoot%\cursors\aero_up.cur'
    Wait          = '%SystemRoot%\cursors\aero_busy.ani'
}
foreach ($c in $esquema.Keys) {
    Set-ItemProperty -Path $cursores -Name $c -Value $esquema[$c] -Type ExpandString
}
Set-ItemProperty -Path $cursores -Name 'Scheme Source'  -Value 2  -Type DWord
Set-ItemProperty -Path $cursores -Name 'CursorBaseSize' -Value 32 -Type DWord
$acess = 'HKCU:\Software\Microsoft\Accessibility'
if (-not (Test-Path $acess)) { New-Item -Path $acess -Force | Out-Null }
Set-ItemProperty -Path $acess -Name CursorSize -Value 1 -Type DWord   # tamanho 1 (normal)
Set-ItemProperty -Path $acess -Name CursorType -Value 0 -Type DWord   # ponteiro branco

# Aplicar de imediato
[WinAPI]::SystemParametersInfo(0x0004, 0, [int[]](6, 10, 1), $GRAVAR) | Out-Null   # SPI_SETMOUSE
[WinAPI]::SystemParametersInfo(0x0071, 0, [IntPtr]10, $GRAVAR)        | Out-Null   # SPI_SETMOUSESPEED
[WinAPI]::SystemParametersInfo(0x0021, 0, [IntPtr]::Zero, $GRAVAR)    | Out-Null   # SPI_SETMOUSEBUTTONSWAP
[WinAPI]::SystemParametersInfo(0x0020, 500, [IntPtr]::Zero, $GRAVAR)  | Out-Null   # SPI_SETDOUBLECLICKTIME
[WinAPI]::SystemParametersInfo(0x005D, 0, [IntPtr]::Zero, $GRAVAR)    | Out-Null   # SPI_SETMOUSETRAILS
[WinAPI]::SystemParametersInfo(0x0060, 0, [IntPtr]::Zero, $GRAVAR)    | Out-Null   # SPI_SETSNAPTODEFBUTTON
[WinAPI]::SystemParametersInfo(0x0067, 400, [IntPtr]::Zero, $GRAVAR)  | Out-Null   # SPI_SETMOUSEHOVERTIME
[WinAPI]::SystemParametersInfo(0x0069, 3, [IntPtr]::Zero, $GRAVAR)    | Out-Null   # SPI_SETWHEELSCROLLLINES
[WinAPI]::SystemParametersInfo(0x006D, 3, [IntPtr]::Zero, $GRAVAR)    | Out-Null   # SPI_SETWHEELSCROLLCHARS
[WinAPI]::SystemParametersInfo(0x0057, 0, [IntPtr]::Zero, $GRAVAR)    | Out-Null   # SPI_SETCURSORS
Escrever '      Rato e ponteiros repostos.' DarkGray

# ---------------------------------------------------------------------------
# 9. Repor o teclado: português (Portugal) e definições de origem
# ---------------------------------------------------------------------------
Escrever '[9/17] A repor o teclado...' Cyan
$PT = '0816:00000816'   # Português (Portugal) - teclado Português
$idiomas = Get-WinUserLanguageList
$soPT = ($idiomas.Count -eq 1 -and $idiomas[0].LanguageTag -eq 'pt-PT' -and
         $idiomas[0].InputMethodTips.Count -eq 1 -and $idiomas[0].InputMethodTips[0] -eq $PT)
if ($soPT) {
    Escrever '      O teclado já estava em Português (Portugal).' DarkGray
} else {
    $lista = New-WinUserLanguageList -Language 'pt-PT'
    $lista[0].InputMethodTips.Clear()
    $lista[0].InputMethodTips.Add($PT)
    Set-WinUserLanguageList -LanguageList $lista -Force -WarningAction SilentlyContinue
    Escrever '      Idioma e teclado repostos: só Português (Portugal), teclado Português.' DarkGray
}
Set-WinDefaultInputMethodOverride -InputTip $PT

# Repetição das teclas: atraso e velocidade de origem
Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name KeyboardDelay -Value '1'
Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name KeyboardSpeed -Value '31'
[WinAPI]::SystemParametersInfo(0x0017, 1,  [IntPtr]::Zero, $GRAVAR) | Out-Null   # SPI_SETKEYBOARDDELAY
[WinAPI]::SystemParametersInfo(0x000B, 31, [IntPtr]::Zero, $GRAVAR) | Out-Null   # SPI_SETKEYBOARDSPEED

# Teclas Presas, de Filtro, de Alternância e do Rato: desligadas
$acessTeclas = 'HKCU:\Control Panel\Accessibility'
Set-ItemProperty -Path "$acessTeclas\StickyKeys"        -Name Flags -Value '510'
Set-ItemProperty -Path "$acessTeclas\Keyboard Response" -Name Flags -Value '126'
Set-ItemProperty -Path "$acessTeclas\ToggleKeys"        -Name Flags -Value '62'
Set-ItemProperty -Path "$acessTeclas\MouseKeys"         -Name Flags -Value '62'
[Definicoes]::ReporTeclasAcessibilidade()

# Teclado no ecrã, Narrador e Lupa: sem arranque automático
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Accessibility' -Name Configuration -Value ''
Get-Process -Name osk, Narrator | Stop-Process -Force
Escrever '      Teclas de acessibilidade desligadas e repetição das teclas reposta.' DarkGray

# ---------------------------------------------------------------------------
# 10. Repor o formato regional, a localização e o fuso horário
# ---------------------------------------------------------------------------
Escrever '[10/17] A repor o formato regional...' Cyan
Set-Culture -CultureInfo 'pt-PT'
Set-WinHomeLocation -GeoId 193                 # Portugal
Set-TimeZone -Id 'GMT Standard Time'           # Lisboa
[Definicoes]::Avisar('intl')
Escrever "      Formato regional: $((Get-Culture).Name); fuso horário: $((Get-TimeZone).Id)." DarkGray

# ---------------------------------------------------------------------------
# 11. Repor as definições de visualização
# ---------------------------------------------------------------------------
Escrever '[11/17] A repor as definições de visualização...' Cyan
$aplicaNaProximaSessao = @()

# Resolução nativa e orientação horizontal
foreach ($l in [Ecra]::ReporResolucao()) { Escrever "      $l" DarkGray }

# Escala do Windows (o "zoom" do ecrã): valor recomendado, 100% nos monitores
# Full HD habituais nas salas de aula
foreach ($l in [Ecra]::ReporEscala()) { Escrever "      $l" DarkGray }
$desk = 'HKCU:\Control Panel\Desktop'
$escalaPersonalizada = (Get-ItemProperty -Path $desk -Name Win8DpiScaling).Win8DpiScaling
if ($escalaPersonalizada -eq 1) {
    Remove-ItemProperty -Path $desk -Name Win8DpiScaling
    Remove-ItemProperty -Path $desk -Name LogPixels
    $aplicaNaProximaSessao += 'escala personalizada'
}

# Tamanho do texto: 100%
$acess = 'HKCU:\Software\Microsoft\Accessibility'
$tamTexto = (Get-ItemProperty -Path $acess -Name TextScaleFactor).TextScaleFactor
if ($tamTexto -and $tamTexto -ne 100) {
    Remove-ItemProperty -Path $acess -Name TextScaleFactor
    $aplicaNaProximaSessao += "tamanho do texto ($tamTexto% para 100%)"
}

# Alto contraste: desligado
if ([Ecra]::DesligarAltoContraste()) { Escrever '      Alto contraste desligado.' DarkGray }

# Filtros de cor: desligados
$filtros = 'HKCU:\Software\Microsoft\ColorFiltering'
if ((Get-ItemProperty -Path $filtros -Name Active).Active -eq 1) {
    Set-ItemProperty -Path $filtros -Name Active -Value 0 -Type DWord
    $aplicaNaProximaSessao += 'filtros de cor'
}

# Lupa: fechada, com ampliação a 100% e sem arranque automático
Get-Process -Name Magnify | Stop-Process -Force
$lupa = 'HKCU:\Software\Microsoft\ScreenMagnifier'
if (-not (Test-Path $lupa)) { New-Item -Path $lupa -Force | Out-Null }
Set-ItemProperty -Path $lupa -Name Magnification -Value 100 -Type DWord
$acessArranque = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Accessibility'
$config = (Get-ItemProperty -Path $acessArranque -Name Configuration).Configuration
if ($config -match 'magnifierpane') {
    $novaConfig = (($config -split ',') | Where-Object { $_ -and $_ -ne 'magnifierpane' }) -join ','
    Set-ItemProperty -Path $acessArranque -Name Configuration -Value $novaConfig
}

# Zoom do Chrome e do Edge: 100% em todos os sites
Remove-TypeData -TypeName System.Array   # evita um erro conhecido do ConvertTo-Json
$utf8SemBOM = New-Object System.Text.UTF8Encoding $false
foreach ($nome in $navegadores.Keys) {
    $base = $navegadores[$nome]
    if (-not (Test-Path $base)) { continue }
    $perfis = @(Get-ChildItem -Path $base -Directory |
              Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
    # O Opera guarda o perfil principal diretamente na pasta base
    if (Test-Path (Join-Path $base 'Preferences')) { $perfis += Get-Item -LiteralPath $base }
    $alterados = 0
    foreach ($perfil in $perfis) {
        $pref = Join-Path $perfil.FullName 'Preferences'
        if (-not (Test-Path $pref)) { continue }
        try {
            $json = [System.IO.File]::ReadAllText($pref) | ConvertFrom-Json -ErrorAction Stop
        } catch { continue }
        if (-not $json.partition) { continue }
        $mudar = $false
        if ($json.partition.default_zoom_level) {
            foreach ($p in $json.partition.default_zoom_level.PSObject.Properties) {
                if ($p.Value -ne 0) { $p.Value = 0.0; $mudar = $true }
            }
        }
        if ($json.partition.per_host_zoom_levels) {
            foreach ($p in $json.partition.per_host_zoom_levels.PSObject.Properties) {
                if (@($p.Value.PSObject.Properties).Count -gt 0) { $mudar = $true }
            }
            if ($mudar) { $json.partition.per_host_zoom_levels = New-Object PSObject }
        }
        if ($mudar) {
            try {
                $novo = $json | ConvertTo-Json -Depth 100 -Compress -ErrorAction Stop
                Copy-Item -Path $pref -Destination "$pref.antes-da-limpeza" -Force
                [System.IO.File]::WriteAllText($pref, $novo, $utf8SemBOM)
                $alterados++
            } catch { }
        }
    }
    Escrever "      $nome`: zoom reposto em $alterados perfil(is)" DarkGray
}

if ($aplicaNaProximaSessao.Count -gt 0) {
    Escrever "      Repostos, com efeito no próximo início de sessão: $($aplicaNaProximaSessao -join ', ')." Yellow
}

# ---------------------------------------------------------------------------
# 12. Repor os ícones originais do ambiente de trabalho
# ---------------------------------------------------------------------------
Escrever '[12/17] A repor os ícones do ambiente de trabalho...' Cyan
$reiniciarExplorador = $false
$explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'

# Retirar do ambiente de trabalho tudo o que não é original (ficheiros,
# pastas e atalhos). Ficam guardados durante 14 dias em
# %LOCALAPPDATA%\LimpezaSala\Retirados do ambiente de trabalho
# Verifica a pasta do ambiente de trabalho em uso (que pode estar no
# OneDrive) e a pasta local do perfil, se forem diferentes.
$ambiente = [Environment]::GetFolderPath('Desktop')
$pastasAmbiente = @($ambiente, "$env:USERPROFILE\Desktop") | Where-Object { $_ } | Select-Object -Unique
$baseRetirados = "$env:LOCALAPPDATA\LimpezaSala\Retirados do ambiente de trabalho"
$totalMovidos = 0; $totalFalhados = 0
foreach ($pa in $pastasAmbiente) {
    $r = Limpar-PastaAmbienteTrabalho $pa $baseRetirados
    $totalMovidos += $r.Movidos; $totalFalhados += $r.Falhados
}
if ($totalMovidos -gt 0) { $reiniciarExplorador = $true }
Escrever "      Ambiente de trabalho: $totalMovidos item(ns) retirado(s), $totalFalhados com erro." DarkGray

# Ambiente de trabalho comum a todas as contas (só administrador o pode limpar;
# sem esses direitos, fica para a tarefa de arranque do computador)
$comum = [Environment]::GetFolderPath('CommonDesktopDirectory')
$noComum = @(Get-ChildItem -LiteralPath $comum -Force | Where-Object {
    $_.Name -ne 'desktop.ini' -and -not ($_.Attributes -band [IO.FileAttributes]::System) -and $ATALHOS_ORIGINAIS -notcontains $_.Name })
if ($noComum.Count -gt 0) {
    if ($eAdministrador) {
        $r = Limpar-PastaAmbienteTrabalho $comum "$env:ProgramData\LimpezaSala\Retirados do ambiente de trabalho comum"
        if ($r.Movidos -gt 0) { $reiniciarExplorador = $true }
    } else {
        Escrever "      Ambiente de trabalho comum: $($noComum.Count) item(ns) a retirar no próximo arranque do computador: $(($noComum | ForEach-Object Name) -join ', ')" DarkGray
    }
}

# Mostrar os ícones do ambiente de trabalho (Ver > Mostrar ícones)
$avancado = "$explorer\Advanced"
if ((Get-ItemProperty -Path $avancado -Name HideIcons).HideIcons -eq 1) {
    Set-ItemProperty -Path $avancado -Name HideIcons -Value 0 -Type DWord
    $reiniciarExplorador = $true
    Escrever '      Ícones do ambiente de trabalho voltaram a ser mostrados.' DarkGray
}

# Ícones do sistema: Este PC e Reciclagem
$iconesSistema = [ordered]@{
    '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' = 'Este PC'
    '{645FF040-5081-101B-9F08-00AA002F954E}' = 'Reciclagem'
}
foreach ($vista in 'NewStartPanel', 'ClassicStartMenu') {
    $chaveVista = "$explorer\HideDesktopIcons\$vista"
    if (-not (Test-Path $chaveVista)) { New-Item -Path $chaveVista -Force | Out-Null }
    foreach ($clsid in $iconesSistema.Keys) {
        if ((Get-ItemProperty -Path $chaveVista -Name $clsid).$clsid -ne 0) {
            Set-ItemProperty -Path $chaveVista -Name $clsid -Value 0 -Type DWord
            $reiniciarExplorador = $true
        }
    }
}

# Nome e imagem originais (apaga nomes e ícones personalizados pelos alunos)
foreach ($clsid in $iconesSistema.Keys) {
    $personalizado = "$explorer\CLSID\$clsid"
    if (Test-Path $personalizado) {
        Remove-Item -Path $personalizado -Recurse -Force
        $reiniciarExplorador = $true
        Escrever "      $($iconesSistema[$clsid]): nome e imagem originais repostos." DarkGray
    }
}

# Atalhos: Google Chrome, Microsoft Edge e Opera (se existir), em sessão anónima e a abrir
# na página inicial da escola
$ambPublico = [Environment]::GetFolderPath('CommonDesktopDirectory')
$shell = New-Object -ComObject WScript.Shell

$programas = @(
    @{ Nome = 'Google Chrome'; Exe = 'chrome.exe'; Args = "--incognito $PAGINA"; Caminhos = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") },
    @{ Nome = 'Microsoft Edge'; Exe = 'msedge.exe'; Args = "--inprivate $PAGINA"; Caminhos = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") },
    @{ Nome = 'Opera Browser'; Exe = 'opera.exe'; Args = "--private $PAGINA"; Caminhos = @(
        "$env:LOCALAPPDATA\Programs\Opera\opera.exe",
        "$env:ProgramFiles\Opera\opera.exe",
        "${env:ProgramFiles(x86)}\Opera\opera.exe",
        "$env:LOCALAPPDATA\Programs\Opera\launcher.exe",
        "$env:ProgramFiles\Opera\launcher.exe") }
)

foreach ($prog in $programas) {
    $destino = $prog.Caminhos | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $destino) { continue }
    $atalhoCerto = Join-Path $ambiente "$($prog.Nome).lnk"

    # Atalhos com outro nome ou outra imagem, apontados para o mesmo destino
    $existentes = @()
    foreach ($pasta in $ambiente, $ambPublico) {
        Get-ChildItem -Path $pasta -Filter *.lnk | ForEach-Object {
            $alvo = $shell.CreateShortcut($_.FullName).TargetPath
            if ($alvo -and ($alvo -eq $destino -or ($prog.Exe -and $alvo -like "*\$($prog.Exe)"))) {
                $existentes += $_
            }
        }
    }

    $noPublico = $existentes | Where-Object { $_.DirectoryName -eq $ambPublico }
    $doAluno   = @($existentes | Where-Object { $_.DirectoryName -eq $ambiente })

    if ($noPublico) {
        # O atalho original está no ambiente de trabalho comum: apagar cópias dos alunos
        foreach ($a in $doAluno) { Remove-Item -Path $a.FullName -Force; $reiniciarExplorador = $true }
        # Como administrador, pôr o atalho comum a abrir a página da escola
        if ($eAdministrador) {
            foreach ($p in $noPublico) {
                $lp = $shell.CreateShortcut($p.FullName)
                if ($lp.Arguments -ne $prog.Args) { $lp.Arguments = $prog.Args; $lp.Save() }
            }
        }
        continue
    }

    # Ficar com um só atalho, com o nome e a imagem originais
    for ($i = 1; $i -lt $doAluno.Count; $i++) { Remove-Item -Path $doAluno[$i].FullName -Force }
    if ($doAluno.Count -ge 1 -and $doAluno[0].FullName -ne $atalhoCerto) {
        if (Test-Path $atalhoCerto) { Remove-Item -Path $atalhoCerto -Force }
        Rename-Item -Path $doAluno[0].FullName -NewName "$($prog.Nome).lnk" -Force
        Escrever "      $($prog.Nome): nome do atalho reposto." DarkGray
    }

    $novo = -not (Test-Path $atalhoCerto)
    $lnk = $shell.CreateShortcut($atalhoCerto)
    if ($novo -or $lnk.TargetPath -ne $destino -or $lnk.IconLocation -ne "$destino,0" -or $lnk.Arguments -ne $prog.Args) {
        $lnk.TargetPath = $destino
        $lnk.Arguments = $prog.Args
        $lnk.WorkingDirectory = Split-Path $destino
        $lnk.IconLocation = "$destino,0"
        $lnk.Save()
        $reiniciarExplorador = $true
        if ($novo) { Escrever "      $($prog.Nome): atalho criado." DarkGray }
        else       { Escrever "      $($prog.Nome): atalho reparado." DarkGray }
    }
}

# Configuração do computador (só quando o script corre como administrador)
if ($eAdministrador) { Aplicar-ConfiguracaoComputador }

# ---------------------------------------------------------------------------
# 13. Repor a barra de tarefas e o menu Iniciar
# ---------------------------------------------------------------------------
Escrever '[13/17] A repor a barra de tarefas e o menu Iniciar...' Cyan
$avanc = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$valoresBarra = 'TaskbarAl', 'TaskbarDa', 'ShowTaskViewButton', 'TaskbarGlomLevel',
                'MMTaskbarEnabled', 'MMTaskbarGlomLevel', 'MMTaskbarMode', 'TaskbarSmallIcons',
                'TaskbarBadges', 'TaskbarSd', 'Start_Layout', 'Start_TrackDocs',
                'Start_TrackProgs', 'Start_IrisRecommendations', 'Start_AccountNotifications'
$repostos = 0
$atuais = Get-ItemProperty -Path $avanc
foreach ($v in $valoresBarra) {
    if ($null -ne $atuais.$v) {
        Remove-ItemProperty -Path $avanc -Name $v
        $repostos++
    }
}
# Caixa de pesquisa com o aspeto de origem
$pesquisa = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
if ($null -ne (Get-ItemProperty -Path $pesquisa -Name SearchboxTaskbarMode).SearchboxTaskbarMode) {
    Remove-ItemProperty -Path $pesquisa -Name SearchboxTaskbarMode
    $repostos++
}
# Barra de tarefas em baixo e sempre visível (sem ocultar automaticamente)
$stuck = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$b = (Get-ItemProperty -Path $stuck -Name Settings).Settings
if ($b -and ($b[8] -ne 2 -or $b[12] -ne 3)) {
    Remove-Item -Path $stuck -Recurse -Force
    $repostos++
}
if ($repostos -gt 0) {
    $reiniciarExplorador = $true
    Escrever "      Barra de tarefas: $repostos definição(ões) reposta(s)." DarkGray
} else {
    Escrever '      A barra de tarefas já estava com as definições de origem.' DarkGray
}
# Menu Iniciar: aplicações afixadas de origem (o Windows recria-as)
$iniciar = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"
foreach ($f in 'start2.bin', 'start.bin') {
    if (Test-Path "$iniciar\$f") { Remove-Item -Path "$iniciar\$f" -Force }
}
Get-Process -Name StartMenuExperienceHost | Stop-Process -Force
Escrever '      Menu Iniciar reposto com as aplicações afixadas de origem.' DarkGray

# ---------------------------------------------------------------------------
# 14. Aplicar o tamanho dos ícones (ícones médios) e confirmar o fundo
# ---------------------------------------------------------------------------
Escrever '[14/17] A aplicar o tamanho dos ícones e o fundo...' Cyan
# 1) Reiniciar o Explorador do Windows quando o passo anterior mudou ícones
#    (o fecho forçado impede que grave as definições antigas)
if ($reiniciarExplorador -or $reiniciarExploradorTema) {
    Get-Process -Name explorer | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name explorer)) { Start-Process explorer.exe }
    Escrever '      Explorador do Windows reiniciado.' DarkGray
}

# 2) Tamanho dos ícones: aplicado diretamente na vista do ambiente de trabalho,
#    como faz o Ctrl+roda do rato (espera até 60 s que o ambiente esteja pronto)
Escrever "      $([AmbTrab]::DefinirTamanhoIcones(48, 60))" DarkGray

# 3) Fundo: voltar a aplicar agora que o ambiente de trabalho está pronto,
#    em todos os monitores, e confirmar o resultado
if ($fundoOriginal) {
    Escrever "      $([AmbTrab]::DefinirFundo($fundoOriginal))" DarkGray
    [WinAPI]::SystemParametersInfo(0x0014, 0, $fundoOriginal, $GRAVAR) | Out-Null
}

# ---------------------------------------------------------------------------
# 15. Pôr o som em silêncio
# ---------------------------------------------------------------------------
Escrever '[15/17] A pôr o som em silêncio...' Cyan
Escrever "      $([Som]::Silenciar(0.5))" DarkGray

# ---------------------------------------------------------------------------
# 16. Ligar o Wi-Fi
# ---------------------------------------------------------------------------
Escrever '[16/17] A ligar o Wi-Fi...' Cyan
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    function Esperar($operacao, [Type]$tipo) {
        $t = $asTask.MakeGenericMethod($tipo).Invoke($null, @($operacao))
        $t.Wait(-1) | Out-Null
        $t.Result
    }
    [Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Radios.RadioAccessStatus, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Radios.RadioState, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null
    Esperar ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus]) | Out-Null
    $radios = Esperar ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
    $radiosWiFi = @($radios | Where-Object { $_.Kind -eq 'WiFi' })
    if ($radiosWiFi.Count -eq 0) {
        Escrever '      Sem Wi-Fi disponível (não existe placa ou está desativada).' DarkGray
    }
    foreach ($r in $radiosWiFi) {
        if ($r.State -eq 'On') {
            Escrever "      Wi-Fi já estava ligado ($($r.Name))." DarkGray
        } else {
            $res = Esperar ($r.SetStateAsync([Windows.Devices.Radios.RadioState]::On)) ([Windows.Devices.Radios.RadioAccessStatus])
            Escrever "      Wi-Fi ligado ($($r.Name)): $res" DarkGray
        }
    }
} catch {
    Escrever "      Não foi possível ligar o Wi-Fi: $($_.Exception.Message)" Yellow
}

# ---------------------------------------------------------------------------
# 17. Verificar contas em "Aceder ao trabalho ou à escola"
# ---------------------------------------------------------------------------
Escrever '[17/17] A verificar contas associadas ao Windows...' Cyan
$estado = dsregcmd /status
$registado = ($estado | Select-String 'WorkplaceJoined\s*:\s*YES')
if ($registado) {
    Escrever ''
    Escrever '      ATENÇÃO: existe uma conta escolar registada neste perfil do' Yellow
    Escrever '      Windows. Deve removê-la manualmente em:' Yellow
    Escrever '      Definições > Contas > Aceder ao trabalho ou à escola' Yellow
    Escrever '      (clique na conta e escolha "Desligar").' Yellow
    if (-not $Automatico) {
        $abrir = Read-Host '      Abrir essa página agora? (S/N)'
        if ($abrir -match '^[sS]') { Start-Process 'ms-settings:workplace' }
    }
} else {
    Escrever '      Nenhuma conta escolar registada no perfil. OK.'
}

# ---------------------------------------------------------------------------
Escrever ''
if ($Automatico) {
    Escrever 'Limpeza automática concluída.' Green
    Stop-Transcript | Out-Null
    exit
}
Escrever '=================================================================' Green
Escrever '  Limpeza concluída.' Green
Escrever '  Termine sessão no Windows (ou reinicie o computador) antes de' Green
Escrever '  o próximo aluno entrar na conta Microsoft 365.' Green
Escrever '=================================================================' Green
Escrever ''
Read-Host 'Prima ENTER para sair'
