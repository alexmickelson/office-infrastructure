## Ansible

run playbook

```bash
ansible-playbook -i hosts.yml --ask-vault-pass main_playbook.yml
ansible-playbook -i hosts.yml --ask-vault-pass -f 5 update-and-reboot-playbook.yml
```

edit secret file

```bash
export EDITOR="code --wait"
ansible-vault edit secrets.yml
```


## network configuration


office-2 netplan
```yml
network:
  version: 2
  ethernets:
    eno1:
      dhcp4: no
      dhcp6: no
  vlans:
    br0.192:
      id: 192
      link: eno1
  bridges:
    br0:
      interfaces: [eno1]
      macaddress: 10:e7:c6:34:e7:20 # change to mac of wired NIC
      addresses: [144.17.92.11/24] # update to ip address of box
      gateway4: 144.17.92.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      parameters:
        stp: false
        forward-delay: 0
```


## more networking ideas

<https://jamielinux.com/docs/libvirt-networking-handbook/routed-network.html>

- routed networking (like a bridge, but only using the interface)


configure host to forward ips
```
net.ipv4.ip_forward = 1
ip -4 route add 144.17.92.17/28 via 203.0.113.86
```

routed.xml
```xml
<network>
  <name>routed</name>
  <bridge name="virbr1" />
  <forward mode="route"/>
  <ip address="144.17.92.20" netmask="255.255.255.240">
    <dhcp>
      <range start="144.17.92.17" end="144.17.92.30"/>
    </dhcp>
  </ip>
</network>
```

```
virsh net-define routed.xml
virsh net-autostart routed
virsh net-start routed
```

vm network config
```xml
<interface type="network">
   <source network="routed"/>
   <mac address="52:54:00:4f:47:f2"/>
</interface>
```

<!-- 10:e7:c6:34:e7:20 -->

## trying to grab multiple ips (this one worked)


```yml

network:
  version: 2
  ethernets:
    eno1:
      dhcp4: false
      addresses: 
        - 144.17.92.12/24
        - 144.17.92.20/24
      gateway4: 144.17.92.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]

```


forward rules
<https://serverfault.com/questions/627608/redirect-all-incoming-traffic-from-a-secondary-public-ip-to-an-internal-ip-addre>
```

sudo iptables -t nat -A  PREROUTING -d 144.17.92.20 -j DNAT --to 192.168.122.191
sudo iptables -t nat -A POSTROUTING -s 192.168.122.191 -j SNAT --to 144.17.92.20
```
