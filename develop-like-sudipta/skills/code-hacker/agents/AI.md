# 🤖 AI — LLM/AI-Specific Vulnerabilities (OWASP LLM Top 10)

## Mission
Find prompt injection, model abuse, and AI-specific security flaws.

## Detection
```bash
rg -n "openai|anthropic|langchain|llama|ollama|transformers|huggingface" -i
rg -n "ChatCompletion|completion|generate|invoke|predict" -i
rg -n "prompt|system_message|user_message|template.*{" -i
rg -n "embeddings|vector.*store|chromadb|pinecone|qdrant|weaviate" -i
```

## Checklist

### LLM01: Prompt Injection
- [ ] User input directly concatenated into system prompts
- [ ] No input sanitization before sending to LLM
- [ ] LLM output used to make decisions (tool calls, DB queries) without validation
- [ ] Indirect injection via documents/URLs fed to LLM (RAG poisoning)

### LLM02: Sensitive Information Disclosure
- [ ] System prompts containing secrets, API keys, internal URLs
- [ ] PII/sensitive data in training data or context window
- [ ] LLM responses not filtered for sensitive data before returning to user
- [ ] Embedding store containing sensitive documents without access control

### LLM03: Supply Chain (AI-specific)
- [ ] Untrusted model files (pickle-based = arbitrary code execution)
- [ ] Unverified model downloads (no checksum validation)
- [ ] Poisoned training data

### LLM04: Data and Model Poisoning
- [ ] User-submitted content used for fine-tuning without review
- [ ] RAG sources not validated for integrity

### LLM05: Insecure Output Handling
- [ ] LLM output rendered as HTML/JS without sanitization (XSS)
- [ ] LLM output used in SQL queries without parameterization
- [ ] LLM output used in system commands
- [ ] LLM-generated code executed without sandboxing

### LLM06: Excessive Agency
- [ ] LLM has direct database write access
- [ ] LLM can execute system commands
- [ ] LLM can send emails/messages without human approval
- [ ] No rate limiting on LLM tool/function calls

### LLM07: Unbounded Consumption
- [ ] No token/cost limits per user
- [ ] No rate limiting on API calls to LLM providers
- [ ] Large context windows without size limits on user input
