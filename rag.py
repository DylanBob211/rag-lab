from embed import embed
from config import container, aoai, semantic_cache
from opentelemetry import trace
import textwrap

tracer = trace.get_tracer(__name__)


def retrieve(question):
    with tracer.start_as_current_span("rag.query") as span:
        span.set_attribute("rag.question", question)
        qv = embed(question)
        with tracer.start_as_current_span("redis.cache_check"):
            hit = semantic_cache.check(prompt=question, vector=qv)
            span.set_attribute("redis.cache_hit", bool(hit))
            if hit:
                return {"answer": hit[0]["response"], "cached": True}

        with tracer.start_as_current_span("cosmos.vector_search"):
            items = list(
                container.query_items(
                    query=textwrap.dedent("""
                            SELECT TOP 3 c.text, VectorDistance(c.embedding, @qv) AS score 
                            FROM c 
                            ORDER BY VectorDistance(c.embedding, @qv)
                            """),
                    parameters=[{"name": "@qv", "value": qv}],
                    enable_cross_partition_query=True,
                )
            )
        span.set_attribute("rag.chunks", len(items))
        context = "\n".join(item["text"] for item in items)
        with tracer.start_as_current_span("aoai.chat"):
            answer = aoai.chat.completions.create(
                model="chat",
                messages=[
                    {
                        "role": "system",
                        "content": "Answer ONLY from the provided context",
                    },
                    {
                        "role": "user",
                        "content": f"CONTEXT:\n{context}\n\nQUESTION:\n{question}",
                    },
                ],
            )
        answer_text = answer.choices[0].message.content
        semantic_cache.store(prompt=question, response=answer_text, vector=qv)
        return {"answer": answer_text, "cached": False}


answer = retrieve("How do I store passwords?")
print(answer)
