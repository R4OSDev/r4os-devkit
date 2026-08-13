# R4OS DevKit

Das R4OS DevKit stellt die lokale Entwicklungsumgebung fuer R4OS bereit. Das
Repository enthaelt nur die Setup-Skripte; SDK, Toolchains und installierte
Hostwerkzeuge werden lokal bezogen und nicht eingecheckt.

    SDK\              Installiertes R4OS SDK
    Setup\            Plattformspezifische Setup-Skripte
    Toolchains\Zig\   Zig-Toolchain
    Boot\Limine\      Limine-Bootloader und Hostwerkzeug
    Emulation\QEMU\   QEMU fuer Build- und Systemtests
    HostTools\        Weitere lokale Entwicklungswerkzeuge

Unter Windows richtet `Setup\Setup_Windows.bat` die festgelegten Versionen von
Zig, Limine und QEMU ein. Alle Pfade werden relativ zum DevKit bestimmt,
Downloads per Pruefsumme kontrolliert und vorhandene passende Installationen
beibehalten.
