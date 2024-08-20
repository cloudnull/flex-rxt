# Deploy the MariaDB Operator and a Galera Cluster

## Create secret

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic mariadb \
                --type Opaque \
                --from-literal=root-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Deploy the mariadb operator

``` shell
cluster_name=`kubectl config view --minify -o jsonpath='{.clusters[0].name}'`
sed -i -e "s/cluster\.local/$cluster_name/" /opt/genestack/base-kustomize/mariadb-operator/kustomization.yaml

test -n "$cluster_name" && kubectl kustomize --enable-helm /opt/genestack/base-kustomize/mariadb-operator | \
  kubectl --namespace mariadb-system apply --server-side --force-conflicts -f -
```

!!! info

    The operator may take a minute to get ready, before deploying the Galera cluster, wait until the webhook is online.

``` shell
kubectl --namespace mariadb-system get pods -w
```

## Deploy the MariaDB Cluster

!!! note

    MariaDB has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

=== "Replication _(Recommended)_"

    Replication in MariaDB involves synchronizing data between a primary database and one or more replicas, enabling continuous data availability even in the event of hardware failures or outages. By using MariaDB replication, OpenStack deployments can achieve improved fault tolerance and load balancing, ensuring that critical cloud services remain operational and performant at all times.

    ``` shell
    kubectl --namespace openstack apply -k /opt/genestack/base-kustomize/mariadb-cluster/base
    ```

=== "Galera"

    MariaDB with Galera Cluster is a popular choice for ensuring high availability and scalability in OpenStack deployments. Galera is a synchronous multi-master replication plugin for MariaDB, allowing all nodes in the cluster to read and write simultaneously while ensuring data consistency across the entire cluster. This setup is particularly advantageous in OpenStack environments, where database operations must be highly reliable and available to support the various services that depend on them. By using Galera with MariaDB, OpenStack deployments can achieve near-instantaneous replication across multiple nodes, enhancing fault tolerance and providing a robust solution for handling the high-demand workloads typical in cloud environments.

    ``` shell
    kubectl --namespace openstack apply -k /opt/genestack/base-kustomize/mariadb-cluster/galera
    ```

=== "AIO"

    In some OpenStack deployments, a single MariaDB server is used to manage the database needs of the cloud environment. While this setup is simpler and easier to manage than clustered solutions, it is typically suited for smaller environments or use cases where high availability and fault tolerance are not critical. A single MariaDB server provides a centralized database service for storing and managing the operational data of OpenStack components, ensuring consistent performance and straightforward management. However, it is important to recognize that this configuration presents a single point of failure, making it less resilient to outages or hardware failures compared to more robust, multi-node setups.

    ``` shell
    kubectl --namespace openstack apply -k /opt/genestack/base-kustomize/mariadb-cluster/aio
    ```

## Verify readiness with the following command

``` shell
kubectl --namespace openstack get mariadbs -w
```
