"""무료 LLM 클라이언트.

OpenAI 호환 `/chat/completions` 엔드포인트를 사용한다. 기본값은 로컬 Ollama
(완전 무료, 키 불필요)이고, 환경 변수로 Groq·OpenRouter 등의 무료 티어도 쓸 수 있다.

    EYEREADER_LLM_URL   (기본 http://localhost:11434/v1)
    EYEREADER_LLM_MODEL (기본 llama3.2)
    EYEREADER_LLM_KEY   (필요한 서비스만)
"""

from __future__ import annotations

import os

import requests

DEFAULT_BASE_URL = "http://localhost:11434/v1"
DEFAULT_MODEL = "llama3.2"

SYSTEM_PROMPT = "You are a helpful reading assistant. Answer in Korean, concisely."


class LLMError(RuntimeError):
    pass


class LLMClient:
    def __init__(self, base_url=None, model=None, api_key=None, session=None, timeout=60):
        self.base_url = (base_url or os.environ.get("EYEREADER_LLM_URL") or DEFAULT_BASE_URL).rstrip("/")
        self.model = model or os.environ.get("EYEREADER_LLM_MODEL") or DEFAULT_MODEL
        self.api_key = api_key or os.environ.get("EYEREADER_LLM_KEY")
        self.session = session or requests.Session()
        self.timeout = timeout

    def chat(self, prompt: str) -> str:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        body = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
        }
        try:
            resp = self.session.post(
                f"{self.base_url}/chat/completions", json=body, headers=headers, timeout=self.timeout
            )
        except Exception as e:  # 연결 실패 등
            raise LLMError(f"LLM 서버에 연결할 수 없습니다: {e}") from e
        if resp.status_code != 200:
            raise LLMError(f"LLM 요청 실패 ({resp.status_code}): {resp.text[:200]}")
        try:
            return resp.json()["choices"][0]["message"]["content"].strip()
        except (KeyError, IndexError, TypeError, ValueError) as e:
            raise LLMError(f"예상치 못한 LLM 응답: {resp.text[:200]}") from e

    def summarize(self, text: str) -> str:
        return self.chat(f"다음 글을 3문장 이내로 요약해 줘:\n\n{text}")

    def explain(self, word: str, context: str = "") -> str:
        return self.chat(f"다음 문맥에서 '{word}'의 뜻을 한두 문장으로 설명해 줘.\n\n문맥: {context}")
