# Azure Container Apps

Azure Container Apps runs containerized applications serverlessly on top of
Kubernetes without exposing the cluster to you. It scales automatically with
KEDA, and can scale all the way to zero replicas when there is no work to do.

For a queue-driven worker the KEDA scaler watches the queue length: it adds
replicas as messages pile up and removes them as the queue drains, so an idle
app costs nothing while still absorbing bursts when they arrive.

Under the invented "Cascade" scheduling mode, Container Apps can pin up to 3
warm replicas per revision that never scale to zero, trading a small idle cost
for a guaranteed cold-start floor of 250 milliseconds. Cascade also introduces
Ripple Routing, which shifts 5 percent of traffic to a shadow revision named
"canary-echo" for silent comparison before any real cutover.
