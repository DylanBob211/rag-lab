from embed import embed
from config import container, aoai

question = "How do I store passwords?"

items = container.query_items(query="""
                      SELECT TOP 3 c.text, VectorDistance(c.embedding, @embeddedQuestion) AS score 
                      FROM c 
                      ORDER BY VectorDistance(c.embedding, @embeddedQuestion)
                      """,
                      parameters=[{ "name": "@embeddedQuestion", "value": embed(question)}],
                      enable_cross_partition_query=True
                      )

context = "\n".join(item["text"] for item in items)
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