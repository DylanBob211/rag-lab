from embed import embed
from config import container, aoai, semantic_cache
from opentelemetry import trace
import textwrap
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()
tracer = trace.get_tracer(__name__)


class Answer(BaseModel):
    answer: str
    cached: bool


@app.get("/ask")
def ask(question: str) -> Answer:
    with tracer.start_as_current_span("rag.query") as span:
        span.set_attribute("rag.question", question)
        qv = embed(question)
        with tracer.start_as_current_span("redis.cache_check"):
            hit = semantic_cache.check(prompt=question, vector=qv)
            span.set_attribute("redis.cache_hit", bool(hit))
            if hit:
                return Answer(answer=hit[0]["response"], cached=True)

        with tracer.start_as_current_span("cosmos.vector_search"):
            items = list(
                container.query_items(
                    query=textwrap.dedent("""
                            SELECT TOP 3 c.text, c.docId, VectorDistance(c.embedding, @qv) AS score 
                            FROM c 
                            WHERE IS_DEFINED(c.embedding)
                            ORDER BY VectorDistance(c.embedding, @qv)
                            """),
                    parameters=[{"name": "@qv", "value": qv}],
                    enable_cross_partition_query=True,
                )
            )
        span.set_attribute("rag.chunks", len(items))
        context = "\n".join(item["text"] for item in items)
        source_ids = list({i["docId"] for i in items})
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
        answer_text = answer.choices[0].message.content or ""
        semantic_cache.store(
            prompt=question,
            response=answer_text,
            vector=qv,
            filters={"doc_ids": ",".join(source_ids)},
        )
        return Answer(answer=answer_text, cached=False)


@app.get("/health")
def health_check() -> dict:
    return {"status": "ok"}
