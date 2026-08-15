# R4OS DevKit

Das R4OS DevKit stellt die lokale Entwicklungsumgebung fuer R4OS bereit. Das
Repository enthaelt nur die Setup-Skripte; SDK, Contract, Toolchains und
installierte Hostwerkzeuge werden lokal bezogen und nicht eingecheckt.

    SDK\Core\         Installiertes R4OS SDK
    SDK\Contract\     Passender Plattform-Contract
    Setup\            Plattformspezifische Setup-Skripte
    Toolchains\Zig\   Zig-Toolchain
    Boot\Limine\      Limine-Bootloader und Hostwerkzeug
    Emulation\QEMU\   QEMU fuer Build- und Systemtests
    HostTools\bin\    Gebaute R4OS-Hostwerkzeuge
    HostTools\Source\ Installierte Hosttool-Quellen

Unter Windows richtet `Setup\Setup_Windows.bat` die festgelegten Versionen von
Zig, Limine und QEMU ein. Danach klont beziehungsweise aktualisiert es die
oeffentlichen Contract-, SDK- und Distribution-Repositories. Daraus baut es
ApiContractGen, R4LContractGen, R4XBuilder, ModuleCatalog, ImageCreator,
NtfsVerify, R4UPack, SerialLinkHost, ImagePlan, PreloadImage und
DefaultRegistry. Git, curl und Windows PowerShell muessen auf dem Host
vorhanden sein.

Alle Ziel-, Temporaer- und Zig-Cachepfade liegen innerhalb des DevKits.
Downloads werden per Pruefsumme kontrolliert, Repositoryupdates erfolgen nur
als Fast-Forward auf `main`, und lokal veraenderte Installations-Checkouts
werden nicht ueberschrieben. Ein unveraenderter erneuter Aufruf behaelt
passende Installationen und bereits aktuelle HostTools bei.

Die Checkouts unter `SDK\` und `HostTools\Source\` sind installierte
Arbeitskopien. Fachliche Aenderungen und Commits erfolgen weiterhin in den
jeweiligen Quell-Repositories, nicht innerhalb des DevKits.
