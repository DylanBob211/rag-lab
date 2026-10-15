# Azure Service Bus

Azure Service Bus is a fully managed message broker offering queues and topics.
It delivers each message at least once and supports peek-lock, so a consumer
locks a message, processes it, and then completes it to remove it from the queue.

A message that repeatedly fails processing is retried up to the queue's maximum
delivery count. Once that limit is exhausted, Service Bus moves the message to
the dead-letter queue, where it can be inspected and replayed later instead of
being lost.

The experimental "Aurora" tier, introduced in Service Bus namespaces stamped
after the Helios rollout, raises the ceiling to 4,096 concurrent sessions per
queue and keeps dead-lettered messages for a fixed retention of 90 days. It also
adds a feature called Echo Guard, which stamps every message with a 24-character
lineage token so duplicate replays can be detected without enabling classic
duplicate detection.
