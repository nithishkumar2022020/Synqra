# Backend API Contract

SYNQRA interfaces with FastAPI-based neural retrieval engines. All communications run over encrypted HTTPS in production or local reverse-forwarded ports during development.

---

## Production Host Configuration

- **Production Base URL**: `https://synqra-api.duckdns.org`
- **Protocol**: HTTPS / TLS 1.3
- **Authentication**: `Authorization: Bearer <CognitoAccessToken>`

---

## Endpoint Specifications

### 1. Ingest PDF Document (`POST /documents`)

Uploads a document for text extraction, chunking, and dense vector embedding.

- **URL**: `https://synqra-api.duckdns.org/documents`
- **Content-Type**: `multipart/form-data`
- **Fields**:
  - `file`: PDF binary stream
  - `chunking_strategy`: String (`"semantic"` or `"fixed"`)

#### Response (`201 Created`)
```json
{
  "document_id": "doc-8f3a12bc",
  "filename": "quantum_error_correction.pdf",
  "chunks": 42,
  "status": "indexed"
}
```

---

### 2. Streaming Retrieval (`POST /questions/stream`)

Dispatches a scoped natural language query and streams incremental answer tokens and timeline telemetry via Server-Sent Events.

- **URL**: `https://synqra-api.duckdns.org/questions/stream`
- **Content-Type**: `application/json`
- **Accept**: `text/event-stream`

#### Request Payload
```json
{
  "question": "Explain topological surface codes.",
  "document_ids": ["doc-8f3a12bc"],
  "top_k": 5,
  "dense_only": false
}
```

#### SSE Stream Protocol (`text/event-stream`)
The server transmits atomic event blocks delimited by double newlines (`\n\n`):

```http
event: status
data: {"step": "vector_search", "message": "Searching HNSW index for top 5 candidates...", "done": false}

event: answer_chunk
data: {"chunk": "Topological surface codes are "}

event: answer_chunk
data: {"chunk": "quantum error-correcting codes "}

event: citations
data: {"citations": [{"id": 1, "document_id": "doc-8f3a12bc", "filename": "quantum_error_correction.pdf", "page": 4, "text": "Surface codes arrange physical qubits in a 2D square lattice..."}]}

event: done
data: {}
```

---

### 3. Fallback Non-Streaming Retrieval (`POST /questions`)

Invoked automatically by `RagStreamRepository` if the streaming endpoint is unreachable or returns `404 Not Found`.

- **URL**: `https://synqra-api.duckdns.org/questions`
- **Content-Type**: `application/json`

#### Response (`200 OK`)
```json
{
  "answer": "Topological surface codes arrange physical qubits on a 2D square lattice [1].",
  "citations": [
    {
      "id": 1,
      "document_id": "doc-8f3a12bc",
      "filename": "quantum_error_correction.pdf",
      "page": 4,
      "text": "Surface codes arrange physical qubits in a 2D square lattice..."
    }
  ]
}
```

---

## Ingestion Status Polling & Timeout Handling

When a document upload begins:
1. File binary is posted to `POST /documents`.
2. Initial response yields `status: "processing"`.
3. Client polls `GET /documents/{document_id}` at 2-second intervals.
4. Asynchronous progress (`15%`, `45%`, `100%`) updates the **Corpus Repository** progress bar.
5. Once indexed, the status transitions to `INDEXED` (`#2E7D32`), making the document available for scoped queries.
