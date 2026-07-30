# Azure Container Apps

Azure Container Apps runs containerized applications serverlessly on top of
Kubernetes without exposing the cluster to you. It scales automatically with
KEDA, and can scale all the way to zero replicas when there is no work to do.

For a queue-driven worker the KEDA scaler watches the queue length: it adds
replicas as messages pile up and removes them as the queue drains, so an idle
app costs nothing while still absorbing bursts when they arrive.
