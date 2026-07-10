from config import aoai


def embed(text: str):
    response = aoai.embeddings.create(input=text, model="embedder", dimensions=1536)
    return response.data[0].embedding
