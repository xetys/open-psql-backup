# Open PSQL Backup for Kubernetes

This project contains a small tool for automatic backup management of PostgreSQL databases.

## Motivation

One of the core features is the **regression based deleting**. This means that you will find maximum three hours old backups from today
while just one backup per week from three months ago. That principle is based on the assumption, that normally we need high frequent
updates only to restore from crash, which possibly happened today or yesterday. If we are interested in data, from past year,
it's ok to have just one snapshot for the week. If a database doesn't grow over time, the overall storage needed for the backup 
converges to a certain size, instead of growing linear. In a real world, you possibly have a linear-like growth of your database size.
A linear grow of backup storage on top, means you might have a growth of n*2 if you backup all three hours. With regression based deleting
and a constant growth of database size, the backup storage growth is still linear.

## How to use

First prepare your target postgres deployments using

``` bash
$ kubectl label deployment xxx is-psql=true
```

There are three types of get open-psql-working in your Kubernetes cluster:

* As a Deployment with daemon mode enabled
* One-Time job
* Cronjob

### Deployment

Just run 

``` 
$ kubectl run open-psql-backup --image=xetys/open-psql-backup --env="DAEMON_MODE=1"
```

To run open-psql-backup in the current namespace. Deploy it in a different namespace if you wan't to watch postgres containers in a other namespace than default.
This deployment method is highly compatible with kuberntes 1.3+, as it only uses deployments.

### Onetime job

Run:

```
$ kubectl apply -f k8s/job.yaml
```

to run the tool one time or

## Cronjob

```
$ kubectl apply -f k8s/cronjob.yaml
```

## How to declare backupable postgres container

Open-psql-backup looks for any deployments with the label `is-psql: true`. Just `kubectl label deploy` those.

Note: Currently this tool expects Postgres instances with no password set!

## Where the backups are stored


The default configuration stores backups in the path `/backups` of the volume named 'backup-dir'. You can change that by using a `PersistentVolumeClaim`
or any other storage strategy you like.


### example with CephFS

The current example shows a binding to a static CephFS using a local secret. With this, you can open the backups 
on all nodes by doing a manual ceph mount on that FS to get the backups. This approach works the same in [rook.io](https://rook.io) and its
shared filesystem.

### example with CIFS (old)

My initial case was using the [Storage Boxes](https://www.hetzner.de/storage-box) from Hetzner, which allow CIFS connections. On every node, I've `cifs-utils` installed and mounted
a CIFS mount into `/var/backups/database`.

This could be achieved by adding

```
//uXXX.your-storagebox.de/backup/db-backup /var/backups/databases cifs user,uid=500,rw,suid,username=uXXX,password=YYY 0 0
```

to `/etc/fstab` and mounting it using

```
$ mount -t cifs -o username=uXXX,password=YYY //uXXX.your-storagebox.de/backup/db-backup /var/backups/databases
```

and then installing open-psql-backup


