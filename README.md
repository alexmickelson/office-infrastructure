## Ansible

run playbook

```bash
ansible-playbook -i hosts.yml --ask-vault-pass main_playbook.yml
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