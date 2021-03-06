# escape=`
ARG WINDOWS_VERSION=1809
ARG PROMETHEUS_VERSION=2.20.1
FROM mcr.microsoft.com/windows/servercore:$WINDOWS_VERSION AS tar
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
ARG PROMETHEUS_VERSION
ENV MHOLT_ARCHIVER_VERSION 2.0
ENV MHOLT_ARCHIVER_SHA256 c23eab86a8f77e446f2b5dbb03305ac9acfb5187108a0090a4bcb3d908fa9785

RUN [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ; `
    Invoke-WebRequest $('https://github.com/mholt/archiver/releases/download/v{0}/archiver_windows_amd64.exe' -f $env:MHOLT_ARCHIVER_VERSION) -OutFile archiver.exe -UseBasicParsing ; `
    if ((Get-FileHash archiver.exe -Algorithm sha256).Hash -ne $env:MHOLT_ARCHIVER_SHA256) { Write-Error 'SHA256 mismatch' }



RUN [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ; `
    Invoke-WebRequest $('https://github.com/prometheus/prometheus/releases/download/v{0}/prometheus-{0}.windows-amd64.tar.gz' -f $env:PROMETHEUS_VERSION) -OutFile 'prometheus.tar.gz' -UseBasicParsing
RUN .\archiver.exe open prometheus.tar.gz
RUN Rename-Item -Path $('C:\prometheus-{0}.windows-amd64' -f $env:PROMETHEUS_VERSION) -NewName 'C:\download'

FROM mcr.microsoft.com/windows/nanoserver:$WINDOWS_VERSION
WORKDIR C:/prometheus
COPY --from=tar C:\Windows\System32\netapi32.dll  C:\Windows\System32\netapi32.dll
COPY --from=tar /download/prometheus.exe      bin/prometheus.exe
COPY --from=tar /download/promtool.exe        bin/promtool.exe
COPY --from=tar /download/prometheus.yml      conf/prometheus.yml
COPY --from=tar /download/console_libraries/  console_libraries/
COPY --from=tar /download/consoles/           consoles/

EXPOSE     9090
ENTRYPOINT [ "/prometheus/bin/prometheus.exe" ]
CMD        [ "--config.file=/prometheus/conf/prometheus.yml", `
             "--storage.tsdb.path=/prometheus/data", `
             "--web.console.libraries=/prometheus/console_libraries", `
             "--web.console.templates=/prometheus/consoles" ]