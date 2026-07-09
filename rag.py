from embed import embed
from config import container, aoai
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

question = "How do I store passwords?"
with tracer.start_as_current_span("rag.query") as span:
  span.set_attribute("rag.question", question)
  with tracer.start_as_current_span("cosmos.vector_search"):
    qv = embed(question)
    items = list(container.query_items(query="""
                          SELECT TOP 3 c.text, VectorDistance(c.embedding, @qv) AS score 
                          FROM c 
                          ORDER BY VectorDistance(c.embedding, @qv)
                          """,
                          parameters=[{ "name": "@qv", "value": qv}],
                          enable_cross_partition_query=True
                          ))
  span.set_attribute("rag.chunks", len(items))
  context = "\n".join(item["text"] for item in items)
  with tracer.start_as_current_span("aoai.chat"):
    answer = aoai.chat.completions.create(
      model="chat",
      messages=[
        { "role": "system", "content": "Answer ONLY from the provided context"},
        { "role": "user", "content": f"""
          CONTEXT:
          {context}

          QUESTION:
          {question}
        """}
      ]
    )

print(answer.choices[0].message.content)