to avoid snaps. I have installed debian on the servers.


1. install debian using graphical installer
2. follow along and set up networking (avoind needing networkmanager?)
3. when given the option, do not install a desktop environment
4. ssh in after reboot
5. configure /etc/resolv.conf
```
nameserver 1.1.1.1
nameserver 8.8.8.8
```
6. configure `/etc/apt/sources.list` <https://medium.com/@kiena/configuring-apt-sources-in-debian-12-ensuring-reliable-software-access-a940ac2ca7f0>
```conf
#deb cdrom:[Debian GNU/Linux 12.5.0 _Bookworm_ - Official amd64 DVD Binary-1 with firmware 20240210-11:28]/ bookworm contrib main non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm contrib non-free non-free-firmware main 
deb http://deb.debian.org/debian/ bookworm-updates contrib non-free non-free-firmware main 
deb http://deb.debian.org/debian/ bookworm-backports contrib non-free non-free-firmware main
```
7. `apt update && apt install -y curl sudo vim && usermod -aG sudo alex`
8. install tailscale, stop service, copy old keys, restart service.