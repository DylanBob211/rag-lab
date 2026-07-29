from typing import Literal
from pydantic import BaseModel


class BlobData(BaseModel):
    url: str
    sequencer: str


class BlobEvent(BaseModel):
    eventType: Literal[
        "Microsoft.Storage.BlobCreated",
        "Microsoft.Storage.BlobDeleted",
    ]
    subject: str
    data: BlobData
