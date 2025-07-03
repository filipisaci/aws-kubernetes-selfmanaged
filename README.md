# aws-kubernetes-selfmanaged

Has no problem with terraform, however when run ansible playbook its breaking at the time of installing CNI.

## Export vars

```
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
export AWS_DEFAULT_REGION=sa-east-1
```

## Steps

```
terraform init
```

```
terraform plan 
```

```
terraform apply 
```

Read ./ansible/README.md and continue the process.

## TODO

- Fix deploy CNI.
