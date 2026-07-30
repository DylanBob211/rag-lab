# Azure Service Bus

Azure Service Bus is a fully managed message broker offering queues and topics.
It delivers each message at least once and supports peek-lock, so a consumer
locks a message, processes it, and then completes it to remove it from the queue.

A message that repeatedly fails processing is retried up to the queue's maximum
delivery count. Once that limit is exhausted, Service Bus moves the message to
the dead-letter queue, where it can be inspected and replayed later instead of
being lost.
