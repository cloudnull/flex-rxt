# Deploy Ceilometer

OpenStack Ceilometer is the telemetry service within the OpenStack ecosystem, responsible for collecting and delivering usage data across various OpenStack services. Ceilometer plays a critical role in monitoring and metering the performance and resource consumption of cloud infrastructure, providing essential data for billing, benchmarking, and operational insights. By aggregating metrics such as CPU usage, network bandwidth, and storage consumption, Ceilometer enables cloud operators to track resource usage, optimize performance, and ensure compliance with service-level agreements. In this document, we will discuss the deployment of OpenStack Ceilometer using Genestack. With Genestack, the deployment of Ceilometer is made more efficient, ensuring that comprehensive and reliable telemetry data is available to support the effective management and optimization of cloud resources.

## Create Secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack create secret generic ceilometer-keystone-admin-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack create secret generic ceilometer-keystone-test-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack create secret generic ceilometer-rabbitmq-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm
helm upgrade --install ceilometer ./ceilometer \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /etc/genestack/helm-configs/ceilometer/ceilometer-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ceilometer.password="$(kubectl --namespace openstack get secret ceilometer-keystone-admin-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.test.password="$(kubectl --namespace openstack get secret ceilometer-keystone-test-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.username="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.ceilometer.password="$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.ceilometer.oslo_messaging_notifications.transport_url="\
rabbit://ceilometer:$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/ceilometer"\
    --set conf.ceilometer.notification.messaging_urls.values="{\
rabbit://ceilometer:$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/ceilometer,\
rabbit://cinder:$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/cinder,\
rabbit://glance:$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/glance,\
rabbit://heat:$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/heat,\
rabbit://keystone:$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/keystone,\
rabbit://neutron:$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/neutron,\
rabbit://nova:$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/nova}" \
    --post-renderer /etc/genestack/kustomize/kustomize.sh \
    --post-renderer-args ceilometer/base
```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Verify Ceilometer Workers

As there is no Ceilometer API, we will do a quick validation against the
Gnocchi API via a series of `openstack metric` commands to confirm that
Ceilometer workers are ingesting metric and event data then persisting them
storage.

### Verify metric resource types exist

The Ceilomter db-sync job will create the various resource types in Gnocchi.
Without them, metrics can't be stored, so let's verify they exist. The
output should include named resource types and some attributes for resources
like `instance`, `instance_disk`, `network`, `volume`, etc.

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric resource-type list
```

### Verify metric resources

Confirm that resources are populating in Gnocchi

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric resource list
```

### Verify metrics

Confirm that metrics can be retrieved from Gnocchi

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric list
```
