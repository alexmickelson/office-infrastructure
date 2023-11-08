edit secret file


```bash
export EDITOR="code --wait"
ansible-vault edit secrets.yml
```


run playbook

```bash
ansible-playbook -i hosts.yml --ask-become-pass --ask-vault-pass main_playbook.yml
```