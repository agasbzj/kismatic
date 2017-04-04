# Running KET with Docker

Assuming you don't want to run KET in daemon mode, you can execute the container the way you normally would the KET binary.
```
docker run -it apprenda/kismatic:latest
```
If you plan on using the provisioning tool, it is recommended to also use a docker volume, since the provisioner will generate an SSH key for your cluster.
```
docker run -itv $(pwd):usr/bin/kismatic apprenda/kismatic:latest
```