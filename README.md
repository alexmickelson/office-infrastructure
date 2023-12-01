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
