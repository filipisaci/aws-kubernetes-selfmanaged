# Before test

*UPDATE your inventory file with instance ip addresses*

# Steps to verify and run

ansible k8s_cluster -i inventory.yaml -m ping
ansible-playbook  -i inventory.yaml  cluster.yaml

ansible all -i inventory.yaml -m ping
